// lib/screens/skill_manager_screen.dart
// Skill Manager Screen - Tabbed interface for skill management
// 技能管理主界面

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../models/skill_model.dart';
import '../providers/skill_provider.dart';
import '../services/skill_manager_service.dart';
import 'mcp_manager_screen.dart';

enum _SkillDiscoverySource { github, curated }

// ═══════════════════════════════════════════════════════════════════════════
// Skill Manager Screen
// ═══════════════════════════════════════════════════════════════════════════

/// Skill Manager Screen
///
/// Tabbed interface:
/// - 已安装: Installed skills list with enable/disable toggle
/// - 发现: Skill marketplace (GitHub skills browser)
/// - MCP: MCP server management overview
///
/// Each skill card:
/// - Icon + Name + Version
/// - Description
/// - Tags (chips)
/// - Author
/// - Install count / Usage count
/// - Enable toggle
class SkillManagerScreen extends ConsumerStatefulWidget {
  const SkillManagerScreen({super.key});

  @override
  ConsumerState<SkillManagerScreen> createState() => _SkillManagerScreenState();
}

class _SkillManagerScreenState extends ConsumerState<SkillManagerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _githubUrlController = TextEditingController();
  _SkillDiscoverySource _discoverySource = _SkillDiscoverySource.github;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      ref.read(skillTabIndexProvider.notifier).state = _tabController.index;
      setState(() {});
    });

    // Initialize the skill manager service
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await ref.read(skillInitProvider.future);
      } catch (e) {
        debugPrint('[SkillManagerScreen] Init error: $e');
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _githubUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabIndex = _tabController.index;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background.withOpacity(0.8),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          '技能中心',
          style: TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: AppTheme.textSecondary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          // Stats badge
          Center(
            child: _buildStatsBadge(),
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppTheme.border, width: 1),
              ),
            ),
            child: TabBar(
              controller: _tabController,
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
              tabs: const [
                Tab(text: '已安装'),
                Tab(text: '发现'),
                Tab(text: 'MCP'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Installed skills
          _buildInstalledTab(),
          // Tab 2: Discover (marketplace)
          _buildDiscoverTab(),
          // Tab 3: MCP overview
          const McpManagerScreen(),
        ],
      ),
      floatingActionButton: tabIndex == 1
          ? FloatingActionButton.extended(
              onPressed: _showGitHubImportSheet,
              backgroundColor: AppTheme.primary,
              icon: const Icon(Icons.code, color: AppTheme.textOnPrimary, size: 20),
              label: const Text(
                'GitHub 导入',
                style: TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textOnPrimary,
                ),
              ),
            )
          : null,
    );
  }

  // ── Stats Badge ────────────────────────────────

  Widget _buildStatsBadge() {
    final statsAsync = ref.watch(skillStatsProvider);
    return Container(
      margin: const EdgeInsets.only(right: 16),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '${statsAsync.enabledSkills}/${statsAsync.installedSkills}',
        style: const TextStyle(
          fontFamily: AppTheme.fontBody,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppTheme.primary,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Tab 1: Installed Skills
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildInstalledTab() {
    final installed = ref.watch(installedSkillsProvider);

    if (installed.isEmpty) {
      return _buildEmptyState(
        icon: Icons.extension_off_outlined,
        title: '暂无已安装技能',
        subtitle: '前往「发现」标签浏览并安装技能',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: installed.length,
      itemBuilder: (context, index) {
        final skill = installed[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SkillCard(
            skill: skill,
            showActions: true,
            onToggle: () => _toggleSkill(skill.id),
            onUninstall: () => _confirmUninstall(skill),
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Tab 2: Discover (Marketplace)
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildDiscoverTab() {
    final searchQuery = ref.watch(skillSearchQueryProvider);
    final sourceLabel = _discoverySource == _SkillDiscoverySource.github ? 'GitHub' : 'Curated GitHub';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              _SourceChip(
                label: 'GitHub',
                selected: _discoverySource == _SkillDiscoverySource.github,
                onTap: () => setState(() => _discoverySource = _SkillDiscoverySource.github),
              ),
              const SizedBox(width: 8),
              _SourceChip(
                label: 'Curated',
                selected: _discoverySource == _SkillDiscoverySource.curated,
                onTap: () => setState(() => _discoverySource = _SkillDiscoverySource.curated),
              ),
            ],
          ),
        ),
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchController,
            onChanged: (value) {
              ref.read(skillSearchQueryProvider.notifier).state = value;
            },
            style: const TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 14,
              color: AppTheme.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: '搜索 $sourceLabel 技能...',
              hintStyle: const TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 14,
                color: AppTheme.textTertiary,
              ),
              prefixIcon: const Icon(Icons.search, size: 20, color: AppTheme.textTertiary),
              suffixIcon: searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18, color: AppTheme.textTertiary),
                      onPressed: () {
                        _searchController.clear();
                        ref.read(skillSearchQueryProvider.notifier).state = '';
                      },
                    )
                  : null,
              filled: true,
              fillColor: AppTheme.surfaceInput,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
              ),
            ),
          ),
        ),

        // Content
        Expanded(
          child: searchQuery.trim().isNotEmpty
              ? _buildSearchResults(searchQuery.trim())
              : _buildTrendingSkills(),
        ),
      ],
    );
  }

  Widget _buildTrendingSkills() {
    final AsyncValue<List<Skill>> trendingAsync = _discoverySource == _SkillDiscoverySource.curated
        ? ref.watch(curatedSkillSearchProvider((query: null, limit: 12)))
        : ref.watch(trendingSkillsProvider);

    return trendingAsync.when(
      data: (skills) {
        if (skills.isEmpty) {
          return _buildEmptyState(
            icon: Icons.explore_outlined,
            title: '暂无推荐技能',
            subtitle: '搜索 GitHub 发现更多技能',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: skills.length,
          itemBuilder: (context, index) {
            final skill = skills[index];
            final isInstalled = ref.watch(skillInstalledProvider(skill.id));
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SkillCard(
                skill: skill,
                showActions: true,
                isInstalled: isInstalled,
                onInstall: () => _previewOrInstallDiscoveredSkill(skill),
              ),
            );
          },
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      ),
      error: (err, _) => _buildErrorState(err.toString()),
    );
  }

  Widget _buildSearchResults(String query) {
    final AsyncValue<List<Skill>> searchAsync = _discoverySource == _SkillDiscoverySource.curated
        ? ref.watch(curatedSkillSearchProvider((query: query, limit: 12)))
        : ref.watch(githubSkillSearchProvider((query: query, language: '')));

    return searchAsync.when(
      data: (skills) {
        if (skills.isEmpty) {
          return _buildEmptyState(
            icon: Icons.search_off_outlined,
            title: '未找到结果',
            subtitle: '尝试其他关键词或从 GitHub 导入',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: skills.length,
          itemBuilder: (context, index) {
            final skill = skills[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SkillCard(
                skill: skill,
                showActions: true,
                onInstall: () => _previewOrInstallDiscoveredSkill(skill),
              ),
            );
          },
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      ),
      error: (err, _) => _buildErrorState(err.toString()),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // GitHub Import Flow
  // ═══════════════════════════════════════════════════════════════════════

  void _showGitHubImportSheet() {
    _githubUrlController.clear();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (context) => Consumer(
        builder: (context, ref, child) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              left: 20,
              right: 20,
              top: 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.textTertiary.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                const Text(
                  '从 GitHub 导入技能',
                  style: TextStyle(
                    fontFamily: AppTheme.fontBody,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '输入 GitHub 仓库地址，格式: github.com/用户名/仓库名',
                  style: TextStyle(
                    fontFamily: AppTheme.fontBody,
                    fontSize: 13,
                    color: AppTheme.textTertiary,
                  ),
                ),
                const SizedBox(height: 16),

                // URL input
                TextField(
                  controller: _githubUrlController,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontBody,
                    fontSize: 14,
                    color: AppTheme.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'https://github.com/user/mobilecode-skill-example',
                    hintStyle: const TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 14,
                      color: AppTheme.textTertiary,
                    ),
                    prefixIcon: const Icon(Icons.link, size: 20, color: AppTheme.textTertiary),
                    filled: true,
                    fillColor: AppTheme.surfaceInput,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Import button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _importFromGitHub(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: AppTheme.textOnPrimary,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text(
                      '导入并预览',
                      style: TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Quick links
                _buildQuickImportLinks(),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildQuickImportLinks() {
    final examples = [
      ('flutter-community/mobilecode-skill-state-management', 'Flutter状态管理'),
      ('mobilecode-team/mobilecode-skill-api', 'API集成助手'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          '快速导入',
          style: TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 12,
            color: AppTheme.textTertiary,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: examples.map((e) {
            final (repo, label) = e;
            return ActionChip(
              label: Text(
                label,
                style: const TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
              backgroundColor: AppTheme.surfaceHover,
              side: const BorderSide(color: AppTheme.border),
              onPressed: () {
                _githubUrlController.text = 'https://github.com/$repo';
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Future<void> _importFromGitHub(BuildContext bottomSheetContext) async {
    final url = _githubUrlController.text.trim();
    if (url.isEmpty) return;

    Navigator.pop(bottomSheetContext);

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      ),
    );

    try {
      final service = ref.read(skillManagerServiceProvider);
      final skill = await service.importFromGitHub(url);

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // Close loading

      // Show preview dialog
      _showSkillPreviewDialog(skill);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // Close loading

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('导入失败: $e'),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showSkillPreviewDialog(Skill skill) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.border),
        ),
        title: Text(
          skill.name,
          style: const TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Version & Author
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'v${skill.version}',
                      style: const TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '@${skill.author}',
                    style: const TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Description
              Text(
                skill.description,
                style: const TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),

              // Tags
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: skill.tags.map((tag) {
                  return _buildTagChip(tag);
                }).toList(),
              ),
              const SizedBox(height: 16),

              _buildManifestAuditSection(skill),
              const SizedBox(height: 16),

              // Actions preview
              if (skill.hasActions) ...[
                _buildPreviewSection('Actions', skill.actions, Icons.bolt),
                const SizedBox(height: 12),
              ],

              // Prompts preview
              if (skill.hasPrompts) ...[
                _buildPreviewSection('Prompts', skill.prompts, Icons.chat_bubble_outline),
                const SizedBox(height: 12),
              ],

              // MCP servers preview
              if (skill.hasMcpServers) ...[
                _buildPreviewSection('MCP Servers', skill.mcpServers, Icons.dns),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              '取消',
              style: TextStyle(fontFamily: AppTheme.fontBody, color: AppTheme.textSecondary),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              _installSkill(skill);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: AppTheme.textOnPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.download, size: 16),
            label: const Text(
              '安装',
              style: TextStyle(fontFamily: AppTheme.fontBody, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManifestAuditSection(Skill skill) {
    final risks = _skillRiskLabels(skill);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.backgroundElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.fact_check_outlined, size: 15, color: AppTheme.primary),
              SizedBox(width: 6),
              Text(
                'Manifest review',
                style: TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            skill.githubUrl ?? 'No GitHub provenance URL recorded.',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 11,
              color: AppTheme.textSecondary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _SkillRiskChip(label: '${skill.actions.length} actions', color: AppTheme.info, icon: Icons.bolt_outlined),
              _SkillRiskChip(label: '${skill.prompts.length} prompts', color: AppTheme.primary, icon: Icons.chat_bubble_outline),
              _SkillRiskChip(label: '${skill.mcpServers.length} MCP', color: skill.hasMcpServers ? AppTheme.warning : AppTheme.textTertiary, icon: Icons.dns_outlined),
              for (final risk in risks) _SkillRiskChip(label: risk.label, color: risk.color, icon: risk.icon),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Install only after source, manifest, MCP commands, and permissions match what you expect.',
            style: TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 11,
              color: AppTheme.textTertiary,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewSection(String title, List<String> items, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.backgroundElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: AppTheme.textTertiary),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...items.map((item) => Padding(
                padding: const EdgeInsets.only(left: 20, bottom: 2),
                child: Text(
                  item,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontCode,
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              )),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Actions
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _toggleSkill(String skillId) async {
    try {
      await ref.read(skillManagerServiceProvider).toggle(skillId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('状态已更新'),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('操作失败: $e'),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _installSkill(Skill skill) async {
    try {
      await ref.read(skillManagerServiceProvider).install(skill);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已安装: ${skill.name}'),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      // Switch to installed tab
      _tabController.animateTo(0);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('安装失败: $e'),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _previewOrInstallDiscoveredSkill(Skill skill) async {
    final shouldPreviewManifest =
        skill.githubUrl != null && (skill.actions.isEmpty && skill.prompts.isEmpty && skill.mcpServers.isEmpty);
    if (!shouldPreviewManifest) {
      await _installSkill(skill);
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      ),
    );

    try {
      final preview = await ref.read(skillManagerServiceProvider).importFromGitHub(skill.githubUrl!);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _showSkillPreviewDialog(preview);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _showSkillPreviewDialog(skill);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('未找到 skill.yaml，已改为仓库元数据预览: $e'),
          backgroundColor: AppTheme.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _confirmUninstall(Skill skill) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.border),
        ),
        title: const Text(
          '确认卸载',
          style: TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        content: Text(
          '确定要卸载「${skill.name}」吗？相关的 Actions 和 Prompt 模板将不再可用。',
          style: const TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 14,
            color: AppTheme.textSecondary,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              '取消',
              style: TextStyle(fontFamily: AppTheme.fontBody, color: AppTheme.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              try {
                await ref.read(skillManagerServiceProvider).uninstall(skill.id);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('已卸载'),
                      backgroundColor: AppTheme.success,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('卸载失败: $e'),
                      backgroundColor: AppTheme.error,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: AppTheme.textOnPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text(
              '卸载',
              style: TextStyle(fontFamily: AppTheme.fontBody, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Shared Widgets
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 56, color: AppTheme.textDisabled.withOpacity(0.4)),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.textTertiary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 13,
              color: AppTheme.textTertiary.withOpacity(0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: AppTheme.error),
          const SizedBox(height: 12),
          Text(
            '加载失败',
            style: TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.error,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 13,
              color: AppTheme.textTertiary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTagChip(String tag) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        tag,
        style: const TextStyle(
          fontFamily: AppTheme.fontBody,
          fontSize: 11,
          color: AppTheme.primary,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Skill Card Widget
// ═══════════════════════════════════════════════════════════════════════════

class _SkillRisk {
  const _SkillRisk({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;
}

List<_SkillRisk> _skillRiskLabels(Skill skill) {
  final risks = <_SkillRisk>[];
  if (skill.githubUrl == null || skill.githubUrl!.trim().isEmpty) {
    risks.add(const _SkillRisk(label: 'No provenance URL', icon: Icons.link_off_outlined, color: AppTheme.warning));
  } else {
    risks.add(const _SkillRisk(label: 'GitHub provenance', icon: Icons.verified_outlined, color: AppTheme.success));
  }
  if (!skill.hasActions && !skill.hasPrompts && !skill.hasMcpServers) {
    risks.add(const _SkillRisk(label: 'Metadata-only manifest', icon: Icons.info_outline, color: AppTheme.textTertiary));
  }
  if (skill.hasMcpServers) {
    risks.add(const _SkillRisk(label: 'MCP command review', icon: Icons.security_outlined, color: AppTheme.warning));
  }
  if (skill.tags.any((tag) => tag.toLowerCase().contains('external'))) {
    risks.add(const _SkillRisk(label: 'External registry source', icon: Icons.travel_explore_outlined, color: AppTheme.warning));
  }
  if (skill.source == SkillSource.github && skill.readme == null) {
    risks.add(const _SkillRisk(label: 'README not fetched', icon: Icons.article_outlined, color: AppTheme.info));
  }
  return risks;
}

class _SkillRiskChip extends StatelessWidget {
  const _SkillRiskChip({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withOpacity(0.26)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 10.5,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// A card widget displaying a single skill with actions.
class SkillCard extends StatelessWidget {
  final Skill skill;
  final bool showActions;
  final bool isInstalled;
  final VoidCallback? onToggle;
  final VoidCallback? onInstall;
  final VoidCallback? onUninstall;

  const SkillCard({
    super.key,
    required this.skill,
    this.showActions = false,
    this.isInstalled = false,
    this.onToggle,
    this.onInstall,
    this.onUninstall,
  });

  @override
  Widget build(BuildContext context) {
    final riskLabels = _skillRiskLabels(skill);
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: skill.isEnabled ? AppTheme.primary.withOpacity(0.3) : AppTheme.border),
      ),
      child: Column(
        children: [
          // Main content
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: icon + name + version + toggle
                Row(
                  children: [
                    // Skill icon
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: skill.isEnabled
                            ? AppTheme.primary.withOpacity(0.15)
                            : AppTheme.surfaceHover,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Icon(
                          _getSkillIcon(skill),
                          size: 20,
                          color: skill.isEnabled ? AppTheme.primary : AppTheme.textTertiary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Name + version
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  skill.name,
                                  style: TextStyle(
                                    fontFamily: AppTheme.fontBody,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: skill.isEnabled ? AppTheme.textPrimary : AppTheme.textSecondary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppTheme.surfaceHover,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'v${skill.version}',
                                  style: const TextStyle(
                                    fontFamily: AppTheme.fontBody,
                                    fontSize: 10,
                                    color: AppTheme.textTertiary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '@${skill.author}',
                                style: const TextStyle(
                                  fontFamily: AppTheme.fontBody,
                                  fontSize: 11,
                                  color: AppTheme.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Toggle or Install button
                    if (showActions) ...[
                      if (skill.isInstalled && onToggle != null)
                        SizedBox(
                          height: 32,
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: Switch.adaptive(
                              value: skill.isEnabled,
                              onChanged: (_) => onToggle!(),
                              activeColor: AppTheme.primary,
                              activeTrackColor: AppTheme.primary.withOpacity(0.3),
                            ),
                          ),
                        )
                      else if (onInstall != null)
                        ElevatedButton(
                          onPressed: onInstall,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: AppTheme.textOnPrimary,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            minimumSize: const Size(0, 32),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(
                            skill.source == SkillSource.github ? '审核' : '安装',
                            style: TextStyle(
                              fontFamily: AppTheme.fontBody,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ],
                ),

                const SizedBox(height: 10),

                // Description
                Text(
                  skill.description,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontBody,
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                    height: 1.5,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),

                const SizedBox(height: 10),

                // Tags
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: skill.tags.map((tag) {
                    return _TagChip(label: tag);
                  }).toList(),
                ),
                if (riskLabels.isNotEmpty && !skill.isInstalled) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final risk in riskLabels.take(3))
                        _SkillRiskChip(label: risk.label, color: risk.color, icon: risk.icon),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Bottom action bar (for installed skills)
          if (skill.isInstalled && (skill.hasActions || skill.hasPrompts || skill.hasMcpServers))
            Container(
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppTheme.divider),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  if (skill.hasActions)
                    _MiniStat(icon: Icons.bolt, label: '${skill.actions.length} Actions'),
                  if (skill.hasPrompts)
                    _MiniStat(icon: Icons.chat_bubble_outline, label: '${skill.prompts.length} Prompts'),
                  if (skill.hasMcpServers)
                    _MiniStat(icon: Icons.dns_outlined, label: '${skill.mcpServers.length} MCP'),
                  const Spacer(),
                  if (skill.usageCount > 0)
                    _MiniStat(icon: Icons.bar_chart, label: '使用 ${skill.usageCount} 次'),
                ],
              ),
            ),

          // Bottom bar for marketplace skills (not installed)
          if (!skill.isInstalled && skill.installCount > 0)
            Container(
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppTheme.divider),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  _MiniStat(
                    icon: Icons.star,
                    label: '${skill.rating.toStringAsFixed(1)}',
                    iconColor: AppTheme.warning,
                  ),
                  const SizedBox(width: 12),
                  _MiniStat(
                    icon: Icons.download,
                    label: '${skill.formattedInstallCount} 次下载',
                  ),
                  const Spacer(),
                  // Source badge
                  _SourceBadge(source: skill.source),
                ],
              ),
            ),

          // Uninstall button row
          if (skill.isInstalled && onUninstall != null)
            Container(
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppTheme.divider),
                ),
              ),
              child: InkWell(
                onTap: onUninstall,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.delete_outline, size: 14, color: AppTheme.error.withOpacity(0.7)),
                      const SizedBox(width: 6),
                      Text(
                        '卸载此技能',
                        style: TextStyle(
                          fontFamily: AppTheme.fontBody,
                          fontSize: 12,
                          color: AppTheme.error.withOpacity(0.7),
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

  IconData _getSkillIcon(Skill skill) {
    if (skill.tags.contains('flutter')) return Icons.flutter_dash;
    if (skill.tags.contains('git')) return Icons.source;
    if (skill.tags.contains('github')) return Icons.code;
    if (skill.tags.contains('api')) return Icons.api;
    if (skill.tags.contains('ui')) return Icons.palette;
    if (skill.source == SkillSource.builtIn) return Icons.verified;
    return Icons.extension;
  }
}

// ── Tag Chip ─────────────────────────────────────

class _SourceChip extends StatelessWidget {
  const _SourceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      onPressed: onTap,
      backgroundColor: selected ? AppTheme.primary.withOpacity(0.16) : AppTheme.surfaceHover,
      side: BorderSide(color: selected ? AppTheme.primary.withOpacity(0.45) : AppTheme.border),
      avatar: Icon(
        selected ? Icons.check_circle_outline : Icons.travel_explore_outlined,
        size: 16,
        color: selected ? AppTheme.primary : AppTheme.textTertiary,
      ),
      label: Text(
        label,
        style: TextStyle(
          fontFamily: AppTheme.fontBody,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: selected ? AppTheme.primary : AppTheme.textSecondary,
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;

  const _TagChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.backgroundElevated,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.border),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: AppTheme.fontBody,
          fontSize: 11,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }
}

// ── Mini Stat ────────────────────────────────────

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? iconColor;

  const _MiniStat({
    required this.icon,
    required this.label,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: iconColor ?? AppTheme.textTertiary),
        const SizedBox(width: 4),
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
}

// ── Source Badge ─────────────────────────────────

class _SourceBadge extends StatelessWidget {
  final SkillSource source;

  const _SourceBadge({required this.source});

  @override
  Widget build(BuildContext context) {
    final color = switch (source) {
      SkillSource.builtIn => AppTheme.success,
      SkillSource.github => const Color(0xFF6E5494), // GitHub purple
      SkillSource.local => AppTheme.info,
      SkillSource.userCreated => AppTheme.accent,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        source.displayName,
        style: TextStyle(
          fontFamily: AppTheme.fontBody,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
