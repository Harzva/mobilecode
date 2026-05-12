import 'package:flutter/material.dart';
import '../themes/app_theme.dart';
import '../widgets/glass_card_widget.dart';
import '../widgets/gradient_button_widget.dart';

/// Team Members Screen - Manage up to 10 team members
/// Features: member list grouped by role, invite flow, search,
/// member detail bottom sheet, role management, permission toggles
class TeamMembersScreen extends StatefulWidget {
  const TeamMembersScreen({super.key});

  @override
  State<TeamMembersScreen> createState() => _TeamMembersScreenState();
}

enum MemberRole { owner, admin, editor, viewer }
enum MemberStatus { online, away, offline }

class TeamMember {
  final String id;
  final String name;
  final String email;
  final String initials;
  final MemberRole role;
  final MemberStatus status;
  final DateTime lastActive;
  final int contributedLines;
  final int completedTasks;
  final String? avatarUrl;
  final String? bio;
  final List<String> skills;

  TeamMember({
    required this.id,
    required this.name,
    required this.email,
    required this.initials,
    required this.role,
    required this.status,
    required this.lastActive,
    this.contributedLines = 0,
    this.completedTasks = 0,
    this.avatarUrl,
    this.bio,
    this.skills = const [],
  });
}

class _TeamMembersScreenState extends State<TeamMembersScreen> {
  final TextEditingController _searchController = TextEditingController();
  final List<TeamMember> _members = [];
  String _searchQuery = '';
  bool _showSearch = false;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadMembers() {
    _members.addAll([
      TeamMember(
        id: '1',
        name: '张明',
        email: 'zhangming@example.com',
        initials: 'ZM',
        role: MemberRole.owner,
        status: MemberStatus.online,
        lastActive: DateTime.now().subtract(const Duration(minutes: 2)),
        contributedLines: 12480,
        completedTasks: 156,
        bio: '全栈开发工程师，专注于 Flutter 和 AI 应用开发',
        skills: ['Flutter', 'Dart', 'AI', 'Node.js'],
      ),
      TeamMember(
        id: '2',
        name: '李华',
        email: 'lihua@example.com',
        initials: 'LH',
        role: MemberRole.admin,
        status: MemberStatus.online,
        lastActive: DateTime.now().subtract(const Duration(minutes: 5)),
        contributedLines: 8920,
        completedTasks: 98,
        bio: '资深前端工程师，UI/UX 设计专家',
        skills: ['React', 'TypeScript', 'UI Design'],
      ),
      TeamMember(
        id: '3',
        name: '王芳',
        email: 'wangfang@example.com',
        initials: 'WF',
        role: MemberRole.admin,
        status: MemberStatus.away,
        lastActive: DateTime.now().subtract(const Duration(hours: 1)),
        contributedLines: 7650,
        completedTasks: 87,
        bio: '后端架构师，微服务专家',
        skills: ['Go', 'Kubernetes', 'Microservices'],
      ),
      TeamMember(
        id: '4',
        name: '赵强',
        email: 'zhaoqiang@example.com',
        initials: 'ZQ',
        role: MemberRole.editor,
        status: MemberStatus.online,
        lastActive: DateTime.now().subtract(const Duration(minutes: 10)),
        contributedLines: 5430,
        completedTasks: 62,
        bio: '移动开发工程师',
        skills: ['Swift', 'Kotlin', 'Flutter'],
      ),
      TeamMember(
        id: '5',
        name: '钱丽',
        email: 'qianli@example.com',
        initials: 'QL',
        role: MemberRole.editor,
        status: MemberStatus.offline,
        lastActive: DateTime.now().subtract(const Duration(hours: 5)),
        contributedLines: 4320,
        completedTasks: 51,
        bio: '数据科学家',
        skills: ['Python', 'ML', 'Data Analysis'],
      ),
      TeamMember(
        id: '6',
        name: '孙伟',
        email: 'sunwei@example.com',
        initials: 'SW',
        role: MemberRole.editor,
        status: MemberStatus.online,
        lastActive: DateTime.now().subtract(const Duration(minutes: 15)),
        contributedLines: 3890,
        completedTasks: 45,
        bio: 'DevOps 工程师',
        skills: ['Docker', 'AWS', 'CI/CD'],
      ),
      TeamMember(
        id: '7',
        name: '周敏',
        email: 'zhoumin@example.com',
        initials: 'ZM',
        role: MemberRole.viewer,
        status: MemberStatus.offline,
        lastActive: DateTime.now().subtract(const Duration(days: 1)),
        contributedLines: 0,
        completedTasks: 0,
        bio: '产品经理',
        skills: ['Product', 'Agile', 'Analytics'],
      ),
      TeamMember(
        id: '8',
        name: '吴磊',
        email: 'wulei@example.com',
        initials: 'WL',
        role: MemberRole.viewer,
        status: MemberStatus.away,
        lastActive: DateTime.now().subtract(const Duration(hours: 3)),
        contributedLines: 0,
        completedTasks: 0,
        bio: '测试工程师',
        skills: ['QA', 'Automation', 'Selenium'],
      ),
    ]);
  }

  List<TeamMember> get _filteredMembers {
    if (_searchQuery.isEmpty) return _members;
    return _members.where((m) {
      return m.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          m.email.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

  List<TeamMember> _membersByRole(MemberRole role) {
    return _filteredMembers.where((m) => m.role == role).toList();
  }

  String _roleLabel(MemberRole role) {
    switch (role) {
      case MemberRole.owner: return '所有者';
      case MemberRole.admin: return '管理员';
      case MemberRole.editor: return '编辑者';
      case MemberRole.viewer: return '查看者';
    }
  }

  Color _roleColor(MemberRole role) {
    switch (role) {
      case MemberRole.owner: return AppTheme.warning;
      case MemberRole.admin: return AppTheme.violet;
      case MemberRole.editor: return AppTheme.cyan;
      case MemberRole.viewer: return AppTheme.textTertiary;
    }
  }

  Color _statusColor(MemberStatus status) {
    switch (status) {
      case MemberStatus.online: return AppTheme.success;
      case MemberStatus.away: return AppTheme.warning;
      case MemberStatus.offline: return AppTheme.textTertiary;
    }
  }

  String _statusLabel(MemberStatus status) {
    switch (status) {
      case MemberStatus.online: return '在线';
      case MemberStatus.away: return '离开';
      case MemberStatus.offline: return '离线';
    }
  }

  String _formatLastActive(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    return '${diff.inDays}天前';
  }

  @override
  Widget build(BuildContext context) {
    final memberCount = _members.length;
    final filteredCount = _filteredMembers.length;

    return Scaffold(
      backgroundColor: AppTheme.deepSpace,
      body: CustomScrollView(
        slivers: [
          // Header
          SliverToBoxAdapter(
            child: _buildHeader(memberCount),
          ),

          // Search bar (toggleable)
          SliverToBoxAdapter(
            child: _buildSearchBar(),
          ),

          // Invite button
          SliverToBoxAdapter(
            child: _buildInviteButton(memberCount),
          ),

          // Members list grouped by role
          if (_membersByRole(MemberRole.owner).isNotEmpty)
            SliverToBoxAdapter(
              child: _buildRoleSection(MemberRole.owner, _membersByRole(MemberRole.owner)),
            ),

          if (_membersByRole(MemberRole.admin).isNotEmpty)
            SliverToBoxAdapter(
              child: _buildRoleSection(MemberRole.admin, _membersByRole(MemberRole.admin)),
            ),

          if (_membersByRole(MemberRole.editor).isNotEmpty)
            SliverToBoxAdapter(
              child: _buildRoleSection(MemberRole.editor, _membersByRole(MemberRole.editor)),
            ),

          if (_membersByRole(MemberRole.viewer).isNotEmpty)
            SliverToBoxAdapter(
              child: _buildRoleSection(MemberRole.viewer, _membersByRole(MemberRole.viewer)),
            ),

          // Empty state
          if (filteredCount == 0)
            const SliverToBoxAdapter(
              child: _EmptyMembersState(),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  Widget _buildHeader(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                const Text(
                  '团队成员',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    gradient: AppTheme.auroraGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count/10',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _showSearch = !_showSearch),
            icon: Icon(
              _showSearch ? Icons.close : Icons.search,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    if (!_showSearch) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _searchQuery = v),
        style: const TextStyle(color: AppTheme.textPrimary),
        decoration: InputDecoration(
          hintText: '搜索成员名称或邮箱...',
          hintStyle: const TextStyle(color: AppTheme.textTertiary),
          prefixIcon: const Icon(Icons.search, color: AppTheme.textTertiary),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                  icon: const Icon(Icons.clear, size: 18, color: AppTheme.textTertiary),
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildInviteButton(int currentCount) {
    final isFull = currentCount >= 10;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: GradientButtonWidget(
        label: isFull ? '成员已满 (10/10)' : '邀请成员',
        icon: Icons.person_add,
        onPressed: isFull ? null : _showInviteSheet,
        isDisabled: isFull,
        width: double.infinity,
      ),
    );
  }

  Widget _buildRoleSection(MemberRole role, List<TeamMember> members) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: _roleColor(role),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${_roleLabel(role)} · ${members.length}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _roleColor(role),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...members.map((member) => _buildMemberCard(member)),
        ],
      ),
    );
  }

  Widget _buildMemberCard(TeamMember member) {
    final isOwner = member.role == MemberRole.owner;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCardWidget(
        onTap: () => _showMemberDetail(member),
        glowEffect: isOwner,
        glowColors: [AppTheme.warning.withOpacity(0.2), Colors.transparent],
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: isOwner
                      ? const LinearGradient(
                          colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : AppTheme.violetGradient,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    member.initials,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          member.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _roleColor(member.role).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _roleLabel(member.role),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _roleColor(member.role),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      member.email,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: _statusColor(member.status),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '${_statusLabel(member.status)} · ${_formatLastActive(member.lastActive)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textTertiary,
                          ),
                        ),
                        if (member.contributedLines > 0) ...[
                          const SizedBox(width: 12),
                          const Text('|', style: TextStyle(fontSize: 11, color: AppTheme.textTertiary)),
                          const SizedBox(width: 12),
                          Icon(Icons.code, size: 12, color: AppTheme.textTertiary),
                          const SizedBox(width: 3),
                          Text(
                            '${member.contributedLines} 行',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textTertiary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Icon(Icons.task_alt, size: 12, color: AppTheme.textTertiary),
                          const SizedBox(width: 3),
                          Text(
                            '${member.completedTasks} 任务',
                            style: const TextStyle(
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
              const Icon(Icons.chevron_right, color: AppTheme.textTertiary, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showInviteSheet() {
    final TextEditingController emailController = TextEditingController();
    MemberRole selectedRole = MemberRole.editor;
    bool isLoading = false;

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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag handle
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
                  '邀请成员',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '通过邮箱邀请团队成员加入 (剩余 ${10 - _members.length} 个名额)',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    hintText: '输入邮箱地址',
                    hintStyle: TextStyle(color: AppTheme.textTertiary),
                    prefixIcon: Icon(Icons.email, color: AppTheme.textTertiary),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '选择角色',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  children: [
                    MemberRole.admin,
                    MemberRole.editor,
                    MemberRole.viewer,
                  ].map((role) {
                    final isSelected = selectedRole == role;
                    return ChoiceChip(
                      label: Text(_roleLabel(role)),
                      selected: isSelected,
                      onSelected: (_) => setModalState(() => selectedRole = role),
                      selectedColor: _roleColor(role).withOpacity(0.25),
                      backgroundColor: AppTheme.surfaceElevated,
                      labelStyle: TextStyle(
                        color: isSelected ? _roleColor(role) : AppTheme.textSecondary,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                      side: BorderSide(
                        color: isSelected ? _roleColor(role) : AppTheme.border,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: GradientButtonWidget(
                    label: '发送邀请',
                    icon: Icons.send,
                    isLoading: isLoading,
                    onPressed: () async {
                      if (emailController.text.trim().isEmpty) return;
                      setModalState(() => isLoading = true);
                      await Future.delayed(const Duration(seconds: 1));
                      if (!context.mounted) return;
                      setState(() {
                        _members.add(TeamMember(
                          id: 'new_${DateTime.now().millisecondsSinceEpoch}',
                          name: emailController.text.split('@')[0],
                          email: emailController.text,
                          initials: emailController.text[0].toUpperCase(),
                          role: selectedRole,
                          status: MemberStatus.offline,
                          lastActive: DateTime.now(),
                        ));
                      });
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('邀请已发送')),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showMemberDetail(TeamMember member) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: AppTheme.surfaceCard,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(
                top: BorderSide(color: AppTheme.violet.withOpacity(0.3)),
              ),
            ),
            child: CustomScrollView(
              controller: scrollController,
              slivers: [
                // Drag handle + header
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppTheme.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Avatar
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          gradient: member.role == MemberRole.owner
                              ? const LinearGradient(
                                  colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                              : AppTheme.violetGradient,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.violet.withOpacity(0.3),
                              blurRadius: 16,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            member.initials,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        member.name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        member.email,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Role badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: _roleColor(member.role).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _roleColor(member.role).withOpacity(0.3),
                          ),
                        ),
                        child: Text(
                          _roleLabel(member.role),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _roleColor(member.role),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Status
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _statusColor(member.status),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${_statusLabel(member.status)} · ${_formatLastActive(member.lastActive)}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      // Bio
                      if (member.bio != null) ...[
                        const SizedBox(height: 20),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            member.bio!,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppTheme.textSecondary,
                              height: 1.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                      // Skills
                      if (member.skills.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          alignment: WrapAlignment.center,
                          children: member.skills.map((skill) {
                            return Chip(
                              label: Text(
                                skill,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              backgroundColor: AppTheme.surfaceElevated,
                              side: const BorderSide(color: AppTheme.border),
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                            );
                          }).toList(),
                        ),
                      ],
                      const SizedBox(height: 24),
                      // Stats row
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildDetailStat(
                                '贡献代码',
                                '${member.contributedLines}',
                                Icons.code,
                                AppTheme.cyan,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildDetailStat(
                                '完成任务',
                                '${member.completedTasks}',
                                Icons.task_alt,
                                AppTheme.success,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildDetailStat(
                                '活跃度',
                                '92%',
                                Icons.trending_up,
                                AppTheme.violet,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Role change (owner only)
                      if (_members.firstWhere((m) => m.role == MemberRole.owner).id == '1')
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: _buildRoleChanger(member),
                        ),
                      const SizedBox(height: 16),
                      // Permission toggles
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: _buildPermissionToggles(member),
                      ),
                      const SizedBox(height: 24),
                      // Activity timeline
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 24),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '最近活动',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildActivityTimeline(),
                      const SizedBox(height: 24),
                      // Remove button
                      if (member.role != MemberRole.owner)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () => _showRemoveConfirm(member),
                              icon: const Icon(Icons.person_remove, color: Colors.white),
                              label: const Text(
                                '移除成员',
                                style: TextStyle(color: Colors.white),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.error,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDetailStat(String label, String value, IconData icon, Color color) {
    return GlassCardWidget(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleChanger(TeamMember member) {
    return GlassCardWidget(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '角色设置',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<MemberRole>(
              value: member.role,
              dropdownColor: AppTheme.surfaceElevated,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: MemberRole.values.where((r) => r != MemberRole.owner).map((role) {
                return DropdownMenuItem(
                  value: role,
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _roleColor(role),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(_roleLabel(role)),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (newRole) {
                if (newRole != null) {
                  setState(() {
                    final idx = _members.indexWhere((m) => m.id == member.id);
                    if (idx >= 0) {
                      _members[idx] = TeamMember(
                        id: member.id,
                        name: member.name,
                        email: member.email,
                        initials: member.initials,
                        role: newRole,
                        status: member.status,
                        lastActive: member.lastActive,
                        contributedLines: member.contributedLines,
                        completedTasks: member.completedTasks,
                        bio: member.bio,
                        skills: member.skills,
                      );
                    }
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionToggles(TeamMember member) {
    final canEdit = member.role == MemberRole.admin || member.role == MemberRole.editor;
    final canDelete = member.role == MemberRole.admin;
    final canInvite = member.role == MemberRole.admin || member.role == MemberRole.owner;
    final canManageApi = member.role == MemberRole.admin || member.role == MemberRole.owner;

    return GlassCardWidget(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '权限管理',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            _PermissionToggle(icon: Icons.edit, label: '可编辑', value: canEdit),
            const Divider(color: AppTheme.border, height: 1),
            _PermissionToggle(icon: Icons.delete, label: '可删除', value: canDelete),
            const Divider(color: AppTheme.border, height: 1),
            _PermissionToggle(icon: Icons.person_add, label: '可邀请', value: canInvite),
            const Divider(color: AppTheme.border, height: 1),
            _PermissionToggle(icon: Icons.api, label: '可管理 API', value: canManageApi),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityTimeline() {
    final activities = [
      {'icon': Icons.commit, 'text': '提交了 5 个文件到 main 分支', 'time': '10分钟前', 'color': AppTheme.violet},
      {'icon': Icons.comment, 'text': '评论了 PR #42', 'time': '1小时前', 'color': AppTheme.cyan},
      {'icon': Icons.merge_type, 'text': '合并了 PR #38', 'time': '3小时前', 'color': AppTheme.success},
      {'icon': Icons.article, 'text': '创建了知识库文章《API 文档》', 'time': '昨天', 'color': AppTheme.cyanLight},
      {'icon': Icons.settings, 'text': '修改了团队设置', 'time': '2天前', 'color': AppTheme.warning},
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: activities.asMap().entries.map((entry) {
          final activity = entry.value;
          final isLast = entry.key == activities.length - 1;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: (activity['color'] as Color).withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      activity['icon'] as IconData,
                      size: 14,
                      color: activity['color'] as Color,
                    ),
                  ),
                  if (!isLast)
                    Container(
                      width: 2,
                      height: 30,
                      color: AppTheme.border,
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activity['text'] as String,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      activity['time'] as String,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  void _showRemoveConfirm(TeamMember member) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceCard,
        title: const Text(
          '移除成员',
          style: TextStyle(color: AppTheme.error),
        ),
        content: Text(
          '确定要将 ${member.name} (${member.email}) 从团队中移除吗？此操作不可撤销。',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              setState(() => _members.removeWhere((m) => m.id == member.id));
              Navigator.pop(context);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${member.name} 已被移除')),
              );
            },
            child: const Text('移除', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
  }
}

/// Permission toggle row widget
class _PermissionToggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;

  const _PermissionToggle({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          Icon(
            value ? Icons.check_circle : Icons.cancel,
            size: 20,
            color: value ? AppTheme.success : AppTheme.error,
          ),
        ],
      ),
    );
  }
}

/// Empty state widget for no members
class _EmptyMembersState extends StatelessWidget {
  const _EmptyMembersState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.violet.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.people_outline,
              size: 40,
              color: AppTheme.textTertiary,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            '还没有团队成员',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '邀请团队成员加入，开始协作开发',
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          GradientButtonWidget(
            label: '邀请成员',
            icon: Icons.person_add,
            onPressed: () {
              // Handled by parent
            },
          ),
        ],
      ),
    );
  }
}
