// lib/screens/deep_dive_screen.dart
// Solo Mode Screen
//
// The dedicated workspace for background tasks.
// Similar to Trae AI's Solo Mode tab.
//
// Layout:
// - Header: "Solo Mode" + active task count
// - Tab bar: Running | Completed | Queue
// - Task cards (each with DeepDiveTaskCard widget)
// - FAB: "New Solo Task"
// - New task sheet:
//   - Text input for request
//   - Quick prompt chips
//   - Priority selector
//   - Submit button
//
// Features:
// - Real-time progress updates (stream)
// - Swipe to dismiss completed tasks
// - Pull-to-refresh
// - Empty state with illustration
// - Smooth animations for status changes
//
// Design: Dark theme, glassmorphism cards
//         Status colors: queued=gray, running=cyan pulse,
//         completed=green, failed=red, paused=yellow

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import '../models/self_use_session.dart';
import '../widgets/deep_dive_task_card.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Extension Helpers for SessionStatus UI
// ═══════════════════════════════════════════════════════════════════════════

extension _SoloScreenStatusUI on SessionStatus {
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

  bool get isTerminal =>
      this == SessionStatus.completed || this == SessionStatus.failed;
}

// ═══════════════════════════════════════════════════════════════════════════
// Solo Mode Service (in-memory task manager)
// ═══════════════════════════════════════════════════════════════════════════

/// Manages multiple Solo Mode tasks with real-time streaming updates.
///
/// Provides:
/// - Task creation, pause, resume, cancel
/// - Real-time progress streams
/// - Task history
/// - Queue management
class DeepDiveModeService {
  DeepDiveModeService._();
  static final DeepDiveModeService _instance = DeepDiveModeService._();
  factory DeepDiveModeService() => _instance;

  final List<SelfUseSession> _tasks = [];
  final _controller = StreamController<List<SelfUseSession>>.broadcast();
  Timer? _mockTimer;

  Stream<List<SelfUseSession>> get tasksStream => _controller.stream;

  List<SelfUseSession> get tasks => List.unmodifiable(_tasks);

  List<SelfUseSession> get activeTasks => _tasks
      .where((t) => t.status == SessionStatus.executing || t.status == SessionStatus.planning)
      .toList();

  List<SelfUseSession> get completedTasks => _tasks
      .where((t) => t.status == SessionStatus.completed || t.status == SessionStatus.failed)
      .toList();

  List<SelfUseSession> get queuedTasks =>
      _tasks.where((t) => t.status == SessionStatus.pending).toList();

  int get activeCount => activeTasks.length;

  void createTask(String request, {List<SelfAction>? actions}) {
    final plannedActions = actions ??
        [
          SelfAction(
            id: generateActionId(),
            action: 'analysis',
            params: {'request': request},
            description: '\u5206\u6790\u9700\u6C42: $request',
          ),
          SelfAction(
            id: generateActionId(),
            action: 'planning',
            params: {},
            description: '\u5236\u5B9A\u6267\u884C\u8BA1\u5212',
          ),
          SelfAction(
            id: generateActionId(),
            action: 'execution',
            params: {},
            description: '\u6267\u884C\u4EFB\u52A1',
          ),
          SelfAction(
            id: generateActionId(),
            action: 'verification',
            params: {},
            description: '\u9A8C\u8BC1\u7ED3\u679C',
          ),
        ];

    final session = SelfUseSession(
      id: generateSessionId(),
      userRequest: request,
      plannedActions: plannedActions,
      planDescription: '\u81EA\u52A8\u6267\u884C\u4EFB\u52A1',
    );

    session.markPlanningStarted();
    session.addLog(SessionLogEntry.info('\u4EFB\u52A1\u5DF2\u521B\u5EFA: "$request"'));
    session.addLog(SessionLogEntry.debug('\u89C4\u5212 ${plannedActions.length} \u4E2A\u6B65\u9AA4'));

    _tasks.insert(0, session);
    _notify();

    // Auto-start after brief planning
    Future.delayed(const Duration(seconds: 2), () {
      if (session.status == SessionStatus.planning) {
        session.markExecutionStarted();
        session.addLog(SessionLogEntry.info('\u5F00\u59CB\u6267\u884C'));
        _notify();
        _startMockProgress(session);
      }
    });
  }

  void pauseTask(String taskId) {
    final task = _tasks.firstWhere((t) => t.id == taskId);
    task.markPaused();
    task.addLog(SessionLogEntry.warning('\u4EFB\u52A1\u5DF2\u6682\u505C'));
    _notify();
  }

  void resumeTask(String taskId) {
    final task = _tasks.firstWhere((t) => t.id == taskId);
    task.markResumed();
    task.addLog(SessionLogEntry.info('\u4EFB\u52A1\u5DF2\u7EE7\u7EED'));
    _notify();
    _startMockProgress(task);
  }

  void cancelTask(String taskId) {
    final task = _tasks.firstWhere((t) => t.id == taskId);
    task.markFailed();
    task.addLog(SessionLogEntry.error('\u4EFB\u52A1\u5DF2\u53D6\u6D88'));
    _notify();
  }

  void removeTask(String taskId) {
    _tasks.removeWhere((t) => t.id == taskId);
    _notify();
  }

  void dismissCompleted(String taskId) {
    _tasks.removeWhere((t) => t.id == taskId);
    _notify();
  }

  void _notify() => _controller.add(List.unmodifiable(_tasks));

  void _startMockProgress(SelfUseSession session) {
    _mockTimer?.cancel();
    _mockTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (session.status != SessionStatus.executing || session.isComplete) {
        timer.cancel();
        return;
      }

      if (session.currentStep < session.plannedActions.length - 1) {
        final action = session.currentAction;
        if (action != null) {
          final success = Random().nextDouble() > 0.1; // 90% success rate
          final result = SelfActionResult(
            actionId: action.id,
            success: success,
            data: success ? {'ok': true} : null,
            error: success ? null : '\u6267\u884C\u5931\u8D25',
            startedAt: DateTime.now().subtract(const Duration(seconds: 1)),
            completedAt: DateTime.now(),
          );
          session.recordResult(result);
          session.addLog(
            success
                ? SessionLogEntry.info('\u5B8C\u6210: ${action.description ?? action.action}')
                : SessionLogEntry.error('\u5931\u8D25: ${action.description ?? action.action}'),
          );
        }
        session.advanceStep();
        _notify();
      } else {
        session.markCompleted();
        session.addLog(SessionLogEntry.info('\u4EFB\u52A1\u5168\u90E8\u5B8C\u6210'));
        _notify();
        timer.cancel();
      }
    });
  }

  void dispose() {
    _mockTimer?.cancel();
    _controller.close();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Solo Mode Screen
// ═══════════════════════════════════════════════════════════════════════════

/// The dedicated Solo Mode workspace for background tasks.
///
/// Similar to Trae AI's Solo tab, this screen provides a complete
/// task management interface where users can:
/// - Monitor all running background tasks
/// - View detailed progress for each task
/// - Browse completed task history
/// - Submit new tasks via the FAB
///
/// The screen features a tabbed interface with three categories:
/// - Running: Active and paused tasks
/// - Completed: Finished tasks (swipe to dismiss)
/// - Queue: Pending tasks waiting to start
///
/// Design: Dark theme with glassmorphism cards, status-colored accents,
///         smooth animations for all state transitions.
class DeepDiveModeScreen extends StatefulWidget {
  const DeepDiveModeScreen({super.key});

  @override
  State<DeepDiveModeScreen> createState() => _DeepDiveModeScreenState();
}

class _DeepDiveModeScreenState extends State<DeepDiveModeScreen>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  // ── Services ──────────────────────────────────────────────────────────

  final DeepDiveModeService _service = DeepDiveModeService();

  // ── Controllers ───────────────────────────────────────────────────────

  late TabController _tabController;
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // ── State ─────────────────────────────────────────────────────────────

  List<SelfUseSession> _tasks = [];
  bool _isSubmitting = false;
  int _selectedPriority = 1; // 0=low, 1=normal, 2=high

  // ── Stream Subscriptions ──────────────────────────────────────────────

  StreamSubscription<List<SelfUseSession>>? _tasksSub;

  // ── Constants ─────────────────────────────────────────────────────────

  static const List<String> _quickPrompts = [
    '\u521B\u5EFA\u4E00\u4E2A\u5F85\u529E\u4E8B\u9879 App',
    '\u4FEE\u590D\u5F53\u524D\u9879\u76EE\u7684\u7F16\u8BD1\u9519\u8BEF',
    '\u7ED9\u9879\u76EE\u6DFB\u52A0\u7528\u6237\u8BA4\u8BC1',
    '\u751F\u6210\u4E00\u4E2A\u767B\u5F55\u9875\u9762',
    '\u63D0\u4EA4\u4EE3\u7801\u5230 GitHub',
    '\u90E8\u7F72\u9879\u76EE\u5230 GitHub Pages',
    '\u91CD\u6784\u5F53\u524D\u6587\u4EF6\u5939\u7ED3\u6784',
    '\u6DFB\u52A0\u5355\u5143\u6D4B\u8BD5',
  ];

  static const List<String> _priorityLabels = ['\u4F4E', '\u6B63\u5E38', '\u9AD8'];
  static const List<Color> _priorityColors = [
    AppTheme.info,
    AppTheme.accent,
    AppTheme.error,
  ];

  // ── Lifecycle ─────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tasksSub = _service.tasksStream.listen((tasks) {
      setState(() => _tasks = tasks);
    });
    _tasks = _service.tasks;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    _tasksSub?.cancel();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  // ── Actions ───────────────────────────────────────────────────────────

  void _submitTask([String? presetText]) {
    final text = (presetText ?? _inputController.text).trim();
    if (text.isEmpty) return;

    HapticFeedback.mediumImpact();
    setState(() => _isSubmitting = true);

    _service.createTask(text);

    _inputController.clear();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => _isSubmitting = false);
        Navigator.of(context).pop(); // Close bottom sheet
      }
    });
  }

  void _showNewTaskSheet() {
    HapticFeedback.mediumImpact();
    _inputController.clear();
    _selectedPriority = 1;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildNewTaskSheet(),
    );
  }

  Future<void> _refresh() async {
    HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 800));
    setState(() {});
  }

  void _pauseTask(String id) => _service.pauseTask(id);
  void _resumeTask(String id) => _service.resumeTask(id);
  void _cancelTask(String id) => _service.cancelTask(id);
  void _dismissTask(String id) => _service.dismissCompleted(id);

  // ════════════════════════════════════════════════════════════════════════
  // Build
  // ════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final activeCount = _service.activeCount;
    final completedCount = _service.completedTasks.length;
    final queuedCount = _service.queuedTasks.length;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: NestedScrollView(
        controller: _scrollController,
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          // ── App Bar ─────────────────────────────────────────────────
          _buildAppBar(activeCount),
          // ── Tab Bar ─────────────────────────────────────────────────
          _buildTabBar(activeCount, completedCount, queuedCount),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildTaskList(_activeTasks, 'running'),
            _buildTaskList(_service.completedTasks, 'completed'),
            _buildTaskList(_service.queuedTasks, 'queued'),
          ],
        ),
      ),
      floatingActionButton: _buildFAB(),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // App Bar
  // ════════════════════════════════════════════════════════════════════════

  Widget _buildAppBar(int activeCount) {
    return SliverAppBar(
      floating: true,
      pinned: true,
      elevation: 0,
      backgroundColor: AppTheme.background.withOpacity(0.9),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.auto_mode,
              size: 20,
              color: AppTheme.textOnPrimary,
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'Solo Mode',
            style: TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          if (activeCount > 0) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.accent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: AppTheme.accent.withOpacity(0.3),
                ),
              ),
              child: Text(
                '$activeCount \u8FD0\u884C\u4E2D',
                style: const TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.accent,
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        // Refresh button
        IconButton(
          icon: const Icon(Icons.refresh, color: AppTheme.textSecondary),
          onPressed: _refresh,
          tooltip: '\u5237\u65B0',
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // Tab Bar
  // ════════════════════════════════════════════════════════════════════════

  Widget _buildTabBar(int active, int completed, int queued) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _TabBarDelegate(
        child: Container(
          color: AppTheme.background.withOpacity(0.95),
          child: TabBar(
            controller: _tabController,
            tabs: [
              _TabItem(label: '\u8FDB\u884C\u4E2D', count: active, color: AppTheme.accent),
              _TabItem(label: '\u5DF2\u5B8C\u6210', count: completed, color: AppTheme.success),
              _TabItem(label: '\u961F\u5217', count: queued, color: AppTheme.textSecondary),
            ],
            labelColor: AppTheme.primary,
            unselectedLabelColor: AppTheme.textTertiary,
            indicatorColor: AppTheme.primary,
            indicatorWeight: 2,
            labelStyle: const TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: const TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // Task List
  // ════════════════════════════════════════════════════════════════════════

  List<SelfUseSession> get _activeTasks =>
      _tasks.where((t) => !t.isComplete && t.status != SessionStatus.pending).toList();

  Widget _buildTaskList(List<SelfUseSession> tasks, String type) {
    if (tasks.isEmpty) {
      return _buildEmptyState(type);
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppTheme.primary,
      backgroundColor: AppTheme.surface,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 100),
        itemCount: tasks.length,
        itemBuilder: (context, index) {
          final task = tasks[index];
          return AnimatedSlide(
            offset: const Offset(0, 0),
            duration: Duration(milliseconds: 200 + (index * 50)),
            child: DeepDiveTaskCard(
              key: ValueKey(task.id),
              session: task,
              dismissible: type == 'completed',
              onPause: () => _pauseTask(task.id),
              onResume: () => _resumeTask(task.id),
              onCancel: () => _cancelTask(task.id),
              onDismiss: () => _dismissTask(task.id),
            ),
          );
        },
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // Empty State
  // ════════════════════════════════════════════════════════════════════════

  Widget _buildEmptyState(String type) {
    final icon = type == 'running'
        ? Icons.play_circle_outline
        : type == 'completed'
            ? Icons.check_circle_outline
            : Icons.queue;
    final title = type == 'running'
        ? '\u6682\u65E0\u8FDB\u884C\u4E2D\u7684\u4EFB\u52A1'
        : type == 'completed'
            ? '\u6682\u65E0\u5DF2\u5B8C\u6210\u7684\u4EFB\u52A1'
            : '\u961F\u5217\u4E3A\u7A7A';
    final subtitle = type == 'running'
        ? '\u70B9\u51FB\u53F3\u4E0B\u89D2\u7684 + \u6309\u94AE\u521B\u5EFA\u65B0\u4EFB\u52A1'
        : type == 'completed'
            ? '\u5DF2\u5B8C\u6210\u7684\u4EFB\u52A1\u4F1A\u663E\u793A\u5728\u8FD9\u91CC'
            : '\u6392\u961F\u4E2D\u7684\u4EFB\u52A1\u4F1A\u663E\u793A\u5728\u8FD9\u91CC';
    final iconColor = type == 'running'
        ? AppTheme.accent
        : type == 'completed'
            ? AppTheme.success
            : AppTheme.textSecondary;

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppTheme.primary,
      backgroundColor: AppTheme.surface,
      child: ListView(
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.2),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        iconColor.withOpacity(0.15),
                        iconColor.withOpacity(0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Icon(icon, size: 40, color: iconColor),
                ),
                const SizedBox(height: 20),
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontBody,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontBody,
                    fontSize: 13,
                    color: AppTheme.textTertiary,
                  ),
                ),
                if (type == 'running') ...[
                  const SizedBox(height: 24),
                  _buildQuickStartHint(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStartHint() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: _quickPrompts.take(3).map((prompt) {
        return ActionChip(
          backgroundColor: AppTheme.surface,
          side: const BorderSide(color: AppTheme.border),
          label: Text(
            prompt,
            style: const TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
          onPressed: () => _submitTask(prompt),
        );
      }).toList(),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // FAB
  // ════════════════════════════════════════════════════════════════════════

  Widget _buildFAB() {
    return FloatingActionButton.extended(
      onPressed: _isSubmitting ? null : _showNewTaskSheet,
      backgroundColor: AppTheme.primary,
      icon: _isSubmitting
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(AppTheme.textOnPrimary),
              ),
            )
          : const Icon(Icons.add, color: AppTheme.textOnPrimary),
      label: Text(
        '\u65B0\u5EFA Solo \u4EFB\u52A1',
        style: TextStyle(
          fontFamily: AppTheme.fontBody,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: _isSubmitting
              ? AppTheme.textOnPrimary.withOpacity(0.6)
              : AppTheme.textOnPrimary,
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // New Task Bottom Sheet
  // ════════════════════════════════════════════════════════════════════════

  Widget _buildNewTaskSheet() {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.surface.withOpacity(0.98),
            AppTheme.backgroundElevated.withOpacity(0.98),
          ],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: AppTheme.primary.withOpacity(0.3)),
          left: const BorderSide(color: AppTheme.border),
          right: const BorderSide(color: AppTheme.border),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.textDisabled.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Title
              const Row(
                children: [
                  Icon(Icons.auto_mode, color: AppTheme.primary, size: 22),
                  SizedBox(width: 10),
                  Text(
                    '\u65B0\u5EFA Solo \u4EFB\u52A1',
                    style: TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 6),
              const Text(
                '\u544A\u8BC9 MobileCode \u4F60\u60F3\u8981\u5B83\u81EA\u52A8\u6267\u884C\u4EC0\u4E48\u4EFB\u52A1',
                style: TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 13,
                  color: AppTheme.textTertiary,
                ),
              ),

              const SizedBox(height: 16),

              // Text input
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.surfaceInput,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.border),
                ),
                child: TextField(
                  controller: _inputController,
                  autofocus: true,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontBody,
                    fontSize: 15,
                    color: AppTheme.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: '\u4F8B\u5982\uFF1A\u521B\u5EFA\u4E00\u4E2A\u5F85\u529E\u4E8B\u9879 App...',
                    hintStyle: TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 14,
                      color: AppTheme.textTertiary.withOpacity(0.7),
                    ),
                    contentPadding: const EdgeInsets.all(16),
                    border: InputBorder.none,
                    suffixIcon: _inputController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear,
                                size: 18, color: AppTheme.textTertiary),
                            onPressed: () => setState(() {
                              _inputController.clear();
                            }),
                          )
                        : null,
                  ),
                  maxLines: 4,
                  minLines: 2,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _submitTask(),
                  onChanged: (_) => setState(() {}),
                ),
              ),

              const SizedBox(height: 16),

              // Priority selector
              const Text(
                '\u4F18\u5148\u7EA7',
                style: TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: List.generate(3, (index) {
                  final isSelected = _selectedPriority == index;
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: index < 2 ? 8 : 0),
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedPriority = index),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? _priorityColors[index].withOpacity(0.15)
                                : AppTheme.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? _priorityColors[index].withOpacity(0.5)
                                  : AppTheme.border,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              _priorityLabels[index],
                              style: TextStyle(
                                fontFamily: AppTheme.fontBody,
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: isSelected
                                    ? _priorityColors[index]
                                    : AppTheme.textTertiary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),

              const SizedBox(height: 16),

              // Quick prompts
              const Text(
                '\u5FEB\u6377\u63D0\u793A',
                style: TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _quickPrompts.map((prompt) {
                  return ActionChip(
                    backgroundColor: AppTheme.surface,
                    side: const BorderSide(color: AppTheme.border),
                    padding: EdgeInsets.zero,
                    label: Text(
                      prompt,
                      style: const TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    onPressed: () => _submitTask(prompt),
                  );
                }).toList(),
              ),

              const SizedBox(height: 20),

              // Submit button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _inputController.text.trim().isNotEmpty && !_isSubmitting
                      ? () => _submitTask()
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: AppTheme.textOnPrimary,
                    disabledBackgroundColor: AppTheme.primaryMuted,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor:
                                AlwaysStoppedAnimation(AppTheme.textOnPrimary),
                          ),
                        )
                      : const Text(
                          '\u5F00\u59CB\u6267\u884C',
                          style: TextStyle(
                            fontFamily: AppTheme.fontBody,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Tab Bar Delegate (for pinned tab bar in sliver)
// ═══════════════════════════════════════════════════════════════════════════

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  _TabBarDelegate({required this.child});

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  double get maxExtent => 48;

  @override
  double get minExtent => 48;

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) =>
      false;
}

// ═══════════════════════════════════════════════════════════════════════════
// Tab Item with Count Badge
// ═══════════════════════════════════════════════════════════════════════════

class _TabItem extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _TabItem({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (count > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontFamily: AppTheme.fontCode,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
