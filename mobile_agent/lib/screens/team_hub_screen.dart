import 'package:flutter/material.dart';
import '../themes/app_theme.dart';
import '../widgets/glass_card_widget.dart';
import '../widgets/gradient_button_widget.dart';
import 'team_members_screen.dart';
import 'team_knowledge_screen.dart';

/// Team Hub Screen - Main team collaboration space
/// Features: activity feed, online presence, shared projects,
/// quick actions, team stats, team chat panel
class TeamHubScreen extends StatefulWidget {
  const TeamHubScreen({super.key});

  @override
  State<TeamHubScreen> createState() => _TeamHubScreenState();
}

enum ActivityType {
  codeCommit,
  memberJoined,
  issueCreated,
  prMerged,
  fileShared,
  comment,
}

class Activity {
  final String id;
  final ActivityType type;
  final String actor;
  final String actorInitials;
  final String action;
  final String target;
  final String? targetDetail;
  final DateTime timestamp;
  final Color accentColor;

  Activity({
    required this.id,
    required this.type,
    required this.actor,
    required this.actorInitials,
    required this.action,
    required this.target,
    this.targetDetail,
    required this.timestamp,
    required this.accentColor,
  });
}

class ChatMessage {
  final String id;
  final String author;
  final String authorInitials;
  final String content;
  final DateTime timestamp;
  final bool isMe;
  final List<String> reactions;

  ChatMessage({
    required this.id,
    required this.author,
    required this.authorInitials,
    required this.content,
    required this.timestamp,
    this.isMe = false,
    this.reactions = const [],
  });
}

class _TeamHubScreenState extends State<TeamHubScreen> {
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  final List<Activity> _activities = [];
  final List<ChatMessage> _chatMessages = [];
  String _activityFilter = '全部';
  String _chatChannel = '一般';
  double _chatPanelHeight = 0;
  bool _isChatOpen = false;

  final List<Map<String, dynamic>> _onlineMembers = [
    {'name': '张明', 'initials': 'ZM', 'color': const Color(0xFF7B2FF7)},
    {'name': '李华', 'initials': 'LH', 'color': const Color(0xFF00D4AA)},
    {'name': '赵强', 'initials': 'ZQ', 'color': const Color(0xFF3B82F6)},
    {'name': '孙伟', 'initials': 'SW', 'color': const Color(0xFFF59E0B)},
    {'name': '王芳', 'initials': 'WF', 'color': const Color(0xFFEC4899)},
    {'name': '钱丽', 'initials': 'QL', 'color': const Color(0xFF10B981)},
    {'name': '周敏', 'initials': 'ZM', 'color': const Color(0xFF8B5CF6)},
  ];

  final List<Map<String, dynamic>> _projects = [
    {
      'name': 'mobile_agent',
      'language': 'Flutter',
      'langColor': const Color(0xFF00D4AA),
      'members': ['ZM', 'LH', 'ZQ'],
      'lastActivity': '5分钟前',
    },
    {
      'name': 'api-service',
      'language': 'Go',
      'langColor': const Color(0xFF3B82F6),
      'members': ['WF', 'SW'],
      'lastActivity': '1小时前',
    },
    {
      'name': 'web-dashboard',
      'language': 'React',
      'langColor': const Color(0xFF61DAFB),
      'members': ['LH', 'ZM', 'WL'],
      'lastActivity': '2小时前',
    },
    {
      'name': 'ml-pipeline',
      'language': 'Python',
      'langColor': const Color(0xFF306998),
      'members': ['QL', 'ZM'],
      'lastActivity': '昨天',
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadActivities();
    _loadChatMessages();
  }

  @override
  void dispose() {
    _chatController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  void _loadActivities() {
    _activities.addAll([
      Activity(
        id: 'a1',
        type: ActivityType.codeCommit,
        actor: '张三',
        actorInitials: 'ZS',
        action: '提交了 3 个文件到',
        target: 'mobile_agent',
        targetDetail: 'feat: add dark mode support',
        timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
        accentColor: AppTheme.success,
      ),
      Activity(
        id: 'a2',
        type: ActivityType.memberJoined,
        actor: '李四',
        actorInitials: 'LS',
        action: '加入了团队',
        target: 'Mobile Agent 开发团队',
        timestamp: DateTime.now().subtract(const Duration(minutes: 15)),
        accentColor: AppTheme.violet,
      ),
      Activity(
        id: 'a3',
        type: ActivityType.issueCreated,
        actor: '王五',
        actorInitials: 'WW',
        action: '创建了 Issue #42:',
        target: '修复内存泄漏',
        targetDetail: '在长时间使用后，内存占用持续增长',
        timestamp: DateTime.now().subtract(const Duration(minutes: 30)),
        accentColor: AppTheme.error,
      ),
      Activity(
        id: 'a4',
        type: ActivityType.prMerged,
        actor: '赵六',
        actorInitials: 'ZL',
        action: '合并了 PR #15',
        target: '优化图片加载性能',
        timestamp: DateTime.now().subtract(const Duration(hours: 1)),
        accentColor: AppTheme.cyan,
      ),
      Activity(
        id: 'a5',
        type: ActivityType.fileShared,
        actor: '钱七',
        actorInitials: 'QQ',
        action: '分享了文件',
        target: 'api_config.dart',
        targetDetail: '包含生产环境 API 配置',
        timestamp: DateTime.now().subtract(const Duration(hours: 2)),
        accentColor: AppTheme.cyanLight,
      ),
      Activity(
        id: 'a6',
        type: ActivityType.comment,
        actor: '孙八',
        actorInitials: 'SB',
        action: '评论了知识库文章',
        target: '《部署指南》',
        targetDetail: '这部分说明很清晰，感谢分享！',
        timestamp: DateTime.now().subtract(const Duration(hours: 3)),
        accentColor: AppTheme.warning,
      ),
      Activity(
        id: 'a7',
        type: ActivityType.codeCommit,
        actor: '张明',
        actorInitials: 'ZM',
        action: '提交了 2 个文件到',
        target: 'api-service',
        targetDetail: 'fix: resolve authentication bug',
        timestamp: DateTime.now().subtract(const Duration(hours: 4)),
        accentColor: AppTheme.success,
      ),
      Activity(
        id: 'a8',
        type: ActivityType.issueCreated,
        actor: '李华',
        actorInitials: 'LH',
        action: '关闭了 Issue #38',
        target: 'UI 适配问题已修复',
        timestamp: DateTime.now().subtract(const Duration(hours: 5)),
        accentColor: AppTheme.error,
      ),
    ]);
  }

  void _loadChatMessages() {
    _chatMessages.addAll([
      ChatMessage(
        id: 'm1',
        author: '张明',
        authorInitials: 'ZM',
        content: '大家早上好！今天的站会改到 10 点开始',
        timestamp: DateTime.now().subtract(const Duration(hours: 2)),
      ),
      ChatMessage(
        id: 'm2',
        author: '李华',
        authorInitials: 'LH',
        content: '收到，已添加到日历',
        timestamp: DateTime.now().subtract(const Duration(hours: 1, minutes: 55)),
      ),
      ChatMessage(
        id: 'm3',
        author: '当前用户',
        authorInitials: 'ME',
        content: '新的 UI 设计稿已经上传到 Figma 了，大家有空看看',
        timestamp: DateTime.now().subtract(const Duration(hours: 1, minutes: 30)),
        isMe: true,
        reactions: ['👍', '👀'],
      ),
      ChatMessage(
        id: 'm4',
        author: '王芳',
        authorInitials: 'WF',
        content: '@当前用户 好的，我下午review一下',
        timestamp: DateTime.now().subtract(const Duration(hours: 1)),
      ),
      ChatMessage(
        id: 'm5',
        author: '赵强',
        authorInitials: 'ZQ',
        content: 'API 文档更新了，新增了错误码说明',
        timestamp: DateTime.now().subtract(const Duration(minutes: 30)),
      ),
      ChatMessage(
        id: 'm6',
        author: '当前用户',
        authorInitials: 'ME',
        content: '赞！正好需要这个',
        timestamp: DateTime.now().subtract(const Duration(minutes: 25)),
        isMe: true,
      ),
      ChatMessage(
        id: 'm7',
        author: '孙伟',
        authorInitials: 'SW',
        content: 'CI/CD 流水线修好了，现在可以正常构建了',
        timestamp: DateTime.now().subtract(const Duration(minutes: 10)),
      ),
    ]);
  }

  IconData _activityIcon(ActivityType type) {
    switch (type) {
      case ActivityType.codeCommit: return Icons.code;
      case ActivityType.memberJoined: return Icons.celebration;
      case ActivityType.issueCreated: return Icons.error_outline;
      case ActivityType.prMerged: return Icons.merge_type;
      case ActivityType.fileShared: return Icons.insert_drive_file;
      case ActivityType.comment: return Icons.comment;
    }
  }

  List<Activity> get _filteredActivities {
    if (_activityFilter == '全部') return _activities;
    final typeMap = {
      '代码': [ActivityType.codeCommit, ActivityType.prMerged],
      '讨论': [ActivityType.comment, ActivityType.fileShared],
      '成员': [ActivityType.memberJoined, ActivityType.issueCreated],
    };
    final types = typeMap[_activityFilter] ?? [];
    return _activities.where((a) => types.contains(a.type)).toList();
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    return '${diff.inDays}天前';
  }

  void _sendChatMessage() {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _chatMessages.add(ChatMessage(
        id: 'new_${DateTime.now().millisecondsSinceEpoch}',
        author: '当前用户',
        authorInitials: 'ME',
        content: text,
        timestamp: DateTime.now(),
        isMe: true,
      ));
    });
    _chatController.clear();
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _toggleChatPanel() {
    setState(() {
      _isChatOpen = !_isChatOpen;
      _chatPanelHeight = _isChatOpen ? 0.6 : 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.deepSpace,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // Header
              SliverToBoxAdapter(
                child: _buildHeader(),
              ),

              // Online presence row
              SliverToBoxAdapter(
                child: _buildOnlinePresence(),
              ),

              // Activity feed
              SliverToBoxAdapter(
                child: _buildActivityFeedHeader(),
              ),

              // Activity cards
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _buildActivityCard(_filteredActivities[index]),
                  childCount: _filteredActivities.length,
                ),
              ),

              // Shared projects
              SliverToBoxAdapter(
                child: _buildSharedProjects(),
              ),

              // Quick actions
              SliverToBoxAdapter(
                child: _buildQuickActions(),
              ),

              // Team stats
              SliverToBoxAdapter(
                child: _buildTeamStats(),
              ),

              // Bottom padding for chat panel
              SliverToBoxAdapter(
                child: SizedBox(height: _isChatOpen ? MediaQuery.of(context).size.height * 0.6 : 80),
              ),
            ],
          ),

          // Team chat panel (slide-up)
          if (_isChatOpen)
            _buildChatPanel(),

          // Chat toggle button
          Positioned(
            right: 16,
            bottom: _isChatOpen ? MediaQuery.of(context).size.height * 0.6 + 16 : 16,
            child: GestureDetector(
              onTap: _toggleChatPanel,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: _isChatOpen
                      ? const LinearGradient(
                          colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : AppTheme.violetGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (_isChatOpen ? AppTheme.error : AppTheme.violet).withOpacity(0.4),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(
                  _isChatOpen ? Icons.close : Icons.chat_bubble,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: AppTheme.violetGradient,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppTheme.violet.withOpacity(0.3),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Center(
              child: Text(
                'MA',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Mobile Agent 开发团队',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.people, size: 14, color: AppTheme.textTertiary),
                    const SizedBox(width: 4),
                    const Text(
                      '10 成员',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppTheme.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      '7 在线',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.success,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('团队设置')),
              );
            },
            icon: const Icon(Icons.settings, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildOnlinePresence() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: GlassCardWidget(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                height: 40,
                width: (_onlineMembers.length * 30) + 10,
                child: Stack(
                  children: _onlineMembers.asMap().entries.map((entry) {
                    return Positioned(
                      left: entry.key * 24,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              (entry.value['color'] as Color),
                              (entry.value['color'] as Color).withOpacity(0.7),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppTheme.surfaceCard,
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            entry.value['initials'] as String,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const TeamMembersScreen(),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppTheme.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '+${_onlineMembers.length - 4} 在线',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      const Icon(
                        Icons.chevron_right,
                        color: AppTheme.textTertiary,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActivityFeedHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            '动态',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: AppTheme.surfaceCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: ['全部', '代码', '讨论', '成员'].map((filter) {
                final isActive = _activityFilter == filter;
                return GestureDetector(
                  onTap: () => setState(() => _activityFilter = filter),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isActive ? AppTheme.violet.withOpacity(0.2) : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      filter,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                        color: isActive ? AppTheme.violet : AppTheme.textTertiary,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityCard(Activity activity) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: GlassCardWidget(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: activity.accentColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _activityIcon(activity.type),
                  size: 20,
                  color: activity.accentColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.textPrimary,
                          height: 1.5,
                        ),
                        children: [
                          TextSpan(
                            text: activity.actor,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          TextSpan(text: ' ${activity.action} '),
                          TextSpan(
                            text: activity.target,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: activity.accentColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (activity.targetDetail != null) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceCard,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                activity.targetDetail!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      _formatTime(activity.timestamp),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSharedProjects() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 0, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 20, bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '共享项目',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                TextButton(
                  onPressed: () {},
                  child: const Text(
                    '查看全部',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.violet,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 130,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(right: 20),
              itemCount: _projects.length,
              itemBuilder: (context, index) {
                return Container(
                  width: 180,
                  margin: const EdgeInsets.only(right: 10),
                  child: _buildProjectCard(_projects[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectCard(Map<String, dynamic> project) {
    return GlassCardWidget(
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: project['langColor'] as Color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  project['language'] as String,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              project['name'] as String,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const Spacer(),
            Row(
              children: [
                SizedBox(
                  height: 24,
                  width: (project['members'] as List).length * 16 + 8,
                  child: Stack(
                    children: (project['members'] as List).asMap().entries.map<Widget>((entry) {
                      return Positioned(
                        left: entry.key * 12,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            gradient: AppTheme.auroraGradient,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppTheme.surfaceCard,
                              width: 1.5,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              entry.value as String,
                              style: const TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const Spacer(),
                Text(
                  project['lastActivity'] as String,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              '快捷操作',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _buildQuickAction(
                  icon: Icons.code,
                  label: '共享代码',
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7B2FF7), Color(0xFF9460FF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  onTap: () => _showSnippetShareSheet(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildQuickAction(
                  icon: Icons.assignment_add,
                  label: '创建任务',
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00D4AA), Color(0xFF0891B2)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  onTap: () => _showCreateTaskSheet(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildQuickAction(
                  icon: Icons.chat,
                  label: '团队聊天',
                  gradient: const LinearGradient(
                    colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  onTap: _toggleChatPanel,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildQuickAction(
                  icon: Icons.menu_book,
                  label: '知识库',
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const TeamKnowledgeScreen(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required Gradient gradient,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: (gradient.colors.first).withOpacity(0.3),
              blurRadius: 12,
              spreadRadius: 1,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, size: 24, color: Colors.white),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamStats() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              '团队统计',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  '代码提交',
                  '156',
                  '次/本周',
                  Icons.commit,
                  AppTheme.violet,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildStatCard(
                  '活跃成员',
                  '8/10',
                  '在线',
                  Icons.people,
                  AppTheme.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  '知识文章',
                  '23',
                  '篇',
                  Icons.article,
                  AppTheme.cyan,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildStatCard(
                  '共享文件',
                  '47',
                  '个',
                  Icons.folder_shared,
                  AppTheme.warning,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    String subtitle,
    IconData icon,
    Color color,
  ) {
    return GlassCardWidget(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 22, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatPanel() {
    final panelHeight = MediaQuery.of(context).size.height * _chatPanelHeight;
    final channels = ['一般', '技术', '随机'];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      height: panelHeight,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surfaceCard,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(color: AppTheme.violet.withOpacity(0.3)),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 20,
              spreadRadius: 0,
            ),
          ],
        ),
        child: Column(
          children: [
            // Drag handle
            GestureDetector(
              onTap: _toggleChatPanel,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            // Channel tabs
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppTheme.border),
                ),
              ),
              child: Row(
                children: [
                  const Text(
                    '团队聊天',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  ...channels.map((channel) {
                    final isActive = _chatChannel == channel;
                    return GestureDetector(
                      onTap: () => setState(() => _chatChannel = channel),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: isActive
                              ? AppTheme.violet.withOpacity(0.2)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          '# $channel',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                            color: isActive ? AppTheme.violet : AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
            // Messages list
            Expanded(
              child: ListView.builder(
                controller: _chatScrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemCount: _chatMessages.length,
                itemBuilder: (context, index) {
                  return _buildChatBubble(_chatMessages[index]);
                },
              ),
            ),
            // Input bar
            _buildChatInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildChatBubble(ChatMessage message) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: message.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!message.isMe) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: AppTheme.violetGradient,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  message.authorInitials,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  message.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!message.isMe)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 2),
                    child: Text(
                      message.author,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: message.isMe
                        ? AppTheme.cyan.withOpacity(0.2)
                        : AppTheme.surfaceElevated,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(message.isMe ? 16 : 4),
                      bottomRight: Radius.circular(message.isMe ? 4 : 16),
                    ),
                    border: Border.all(
                      color: message.isMe
                          ? AppTheme.cyan.withOpacity(0.3)
                          : AppTheme.border,
                    ),
                  ),
                  child: Text(
                    message.content,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppTheme.textPrimary,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatTime(message.timestamp),
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                    // Reactions
                    if (message.reactions.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      ...message.reactions.map((reaction) {
                        return Container(
                          margin: const EdgeInsets.only(right: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceElevated,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: Text(reaction, style: const TextStyle(fontSize: 12)),
                        );
                      }).toList(),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (message.isMe) ...[
            const SizedBox(width: 8),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: AppTheme.auroraGradient,
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Text(
                  'ME',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChatInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        border: Border(
          top: BorderSide(color: AppTheme.border),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.emoji_emotions, color: AppTheme.textTertiary),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.alternate_email, color: AppTheme.textTertiary),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _chatController,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                ),
                decoration: const InputDecoration(
                  hintText: '输入消息...',
                  hintStyle: TextStyle(color: AppTheme.textTertiary),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onSubmitted: (_) => _sendChatMessage(),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _sendChatMessage,
              child: Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  gradient: AppTheme.violetGradient,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.send,
                  size: 18,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSnippetShareSheet() {
    final TextEditingController snippetController = TextEditingController();
    final TextEditingController descController = TextEditingController();
    String selectedLang = 'Dart';
    final languages = ['Dart', 'JavaScript', 'Python', 'Go', 'Swift', 'Kotlin'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              top: 20,
              left: 20,
              right: 20,
            ),
            decoration: BoxDecoration(
              color: AppTheme.surfaceCard,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(
                top: BorderSide(color: AppTheme.violet.withOpacity(0.3)),
              ),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppTheme.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '共享代码片段',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '与团队分享你的代码片段',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: descController,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: const InputDecoration(
                      hintText: '描述（可选）',
                      hintStyle: TextStyle(color: AppTheme.textTertiary),
                      prefixIcon: Icon(Icons.description, color: AppTheme.textTertiary),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: snippetController,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontFamily: 'JetBrainsMono',
                      fontSize: 13,
                    ),
                    maxLines: 8,
                    decoration: const InputDecoration(
                      hintText: '粘贴代码...',
                      hintStyle: TextStyle(
                        color: AppTheme.textTertiary,
                        fontFamily: 'JetBrainsMono',
                      ),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: languages.map((lang) {
                      final isSelected = selectedLang == lang;
                      return ChoiceChip(
                        label: Text(lang),
                        selected: isSelected,
                        onSelected: (_) =>
                            setModalState(() => selectedLang = lang),
                        selectedColor: AppTheme.violet.withOpacity(0.25),
                        backgroundColor: AppTheme.surfaceElevated,
                        labelStyle: TextStyle(
                          color: isSelected ? AppTheme.violet : AppTheme.textSecondary,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                        side: BorderSide(
                          color: isSelected ? AppTheme.violet : AppTheme.border,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: GradientButtonWidget(
                      label: '发送',
                      icon: Icons.send,
                      onPressed: () {
                        if (snippetController.text.trim().isEmpty) return;
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('代码片段已共享')),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showCreateTaskSheet() {
    final TextEditingController titleController = TextEditingController();
    final TextEditingController descController = TextEditingController();
    String selectedPriority = '中';
    final priorities = ['高', '中', '低'];
    final priorityColors = [AppTheme.error, AppTheme.warning, AppTheme.success];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              top: 20,
              left: 20,
              right: 20,
            ),
            decoration: BoxDecoration(
              color: AppTheme.surfaceCard,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(
                top: BorderSide(color: AppTheme.violet.withOpacity(0.3)),
              ),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppTheme.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '创建任务',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: titleController,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: const InputDecoration(
                      hintText: '任务标题',
                      hintStyle: TextStyle(color: AppTheme.textTertiary),
                      prefixIcon: Icon(Icons.title, color: AppTheme.textTertiary),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descController,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: '任务描述（可选）',
                      hintStyle: TextStyle(color: AppTheme.textTertiary),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '优先级',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: priorities.asMap().entries.map((entry) {
                      final isSelected = selectedPriority == entry.value;
                      final color = priorityColors[entry.key];
                      return ChoiceChip(
                        label: Text(entry.value),
                        selected: isSelected,
                        onSelected: (_) =>
                            setModalState(() => selectedPriority = entry.value),
                        selectedColor: color.withOpacity(0.25),
                        backgroundColor: AppTheme.surfaceElevated,
                        labelStyle: TextStyle(
                          color: isSelected ? color : AppTheme.textSecondary,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                        side: BorderSide(
                          color: isSelected ? color : AppTheme.border,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: GradientButtonWidget(
                      label: '创建任务',
                      icon: Icons.add_task,
                      onPressed: () {
                        if (titleController.text.trim().isEmpty) return;
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('任务已创建')),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
