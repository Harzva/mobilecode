import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';

import '../core/theme.dart';
import '../core/constants.dart';
import '../models/project.dart';
import '../models/file_item.dart';
import '../services/project_manager.dart';
import '../services/storage_service.dart';
import '../widgets/project_card_widget.dart';
import 'project_detail_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ProjectScreen - Full-Featured Project Management
// ═══════════════════════════════════════════════════════════════════════════

/// The main projects screen with comprehensive project management features.
///
/// Features:
/// - Unlimited project creation with 6 templates
/// - Search, sort, and filter by category
/// - Import (ZIP, GitHub) and Export (ZIP)
/// - Project stats dashboard
/// - Git integration
/// - Archive/unarchive (soft delete)
/// - Duplicate, rename, favorite
/// - Color coding and tags
class ProjectScreen extends StatefulWidget {
  const ProjectScreen({super.key});

  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen>
    with TickerProviderStateMixin {
  late final ProjectManager _projectManager;
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  late final ScrollController _scrollController;
  late final TabController _tabController;

  List<Project> _projects = [];
  List<Project> _filteredProjects = [];
  bool _isLoading = true;
  bool _showStats = false;
  bool _isSearching = false;

  String _currentCategory = ProjectCategory.all;
  ProjectSortOption _currentSort = ProjectSortOption.recent;

  GlobalStats? _globalStats;

  @override
  void initState() {
    super.initState();
    _projectManager = ProjectManager(storage: StorageService());
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode();
    _scrollController = ScrollController();
    _tabController = TabController(length: 5, vsync: this);

    _searchController.addListener(_onSearchChanged);
    _loadProjects();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    _tabController.dispose();
    _projectManager.dispose();
    super.dispose();
  }

  // ─── Data Loading ──────────────────────────────────────────────────

  Future<void> _loadProjects() async {
    setState(() => _isLoading = true);
    try {
      final projects = await _projectManager.getAllProjects();
      final sorted = _projectManager.sortProjects(projects, _currentSort);

      setState(() {
        _projects = sorted;
        _applyFilters();
        _isLoading = false;
      });

      // Load global stats in background.
      _loadGlobalStats();
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Failed to load projects: $e');
    }
  }

  Future<void> _loadGlobalStats() async {
    try {
      final stats = await _projectManager.getGlobalStats();
      if (mounted) setState(() => _globalStats = stats);
    } catch (_) {
      // Silently fail stats loading.
    }
  }

  void _onSearchChanged() {
    _applyFilters();
  }

  void _applyFilters() {
    var result = List<Project>.from(_projects);

    // Apply category filter.
    if (_currentCategory != ProjectCategory.all) {
      // Category filtering is done at load time via getProjectsByCategory.
      // For now filter from loaded list.
    }

    // Apply search filter.
    final query = _searchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      result = result.where((p) {
        return p.name.toLowerCase().contains(query) ||
            p.description.toLowerCase().contains(query) ||
            p.language.toLowerCase().contains(query);
      }).toList();
    }

    setState(() => _filteredProjects = result);
  }

  Future<void> _filterByCategory(String category) async {
    setState(() {
      _isLoading = true;
      _currentCategory = category;
    });

    try {
      List<Project> projects;
      if (category == ProjectCategory.archive) {
        projects = await _projectManager.getArchivedProjects();
      } else if (category == ProjectCategory.all) {
        projects = await _projectManager.getAllProjects();
      } else {
        projects = await _projectManager.getProjectsByCategory(category);
      }

      final sorted = _projectManager.sortProjects(projects, _currentSort);
      setState(() {
        _projects = sorted;
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _sortProjects(ProjectSortOption sort) {
    setState(() {
      _currentSort = sort;
      _projects = _projectManager.sortProjects(_projects, sort);
      _applyFilters();
    });
  }

  // ─── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            // App bar with title and actions
            _buildAppBar(),

            // Stats dashboard (collapsible)
            if (_showStats && _globalStats != null) _buildStatsDashboard(),

            // Search and filter bar
            _buildSearchAndFilters(),

            // Category tabs
            _buildCategoryTabs(),

            // Projects grid or empty state
            _isLoading ? _buildLoading() : _buildProjectGrid(),

            // Bottom padding
            const SliverToBoxAdapter(
              child: SizedBox(height: 100),
            ),
          ],
        ),
      ),
      floatingActionButton: _buildFAB(),
    );
  }

  // ─── App Bar ───────────────────────────────────────────────────────

  Widget _buildAppBar() {
    return SliverToBoxAdapter(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Projects',
                    style: TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_filteredProjects.length} ${_filteredProjects.length == 1 ? 'project' : 'projects'}',
                    style: const TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 13,
                      color: AppTheme.textTertiary,
                    ),
                  ),
                ],
              ),
            ),

            // Stats toggle
            _IconButton(
              icon: _showStats
                  ? Icons.analytics
                  : Icons.analytics_outlined,
              onTap: () => setState(() => _showStats = !_showStats),
              isActive: _showStats,
            ),

            // Sort
            PopupMenuButton<ProjectSortOption>(
              color: AppTheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppTheme.border),
              ),
              icon: const Icon(
                Icons.sort,
                color: AppTheme.textSecondary,
                size: 22,
              ),
              onSelected: _sortProjects,
              itemBuilder: (context) => ProjectSortOption.values
                  .map(
                    (opt) => PopupMenuItem(
                      value: opt,
                      child: Row(
                        children: [
                          Icon(
                            opt.icon,
                            size: 18,
                            color: _currentSort == opt
                                ? AppTheme.primary
                                : AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            opt.label,
                            style: TextStyle(
                              fontFamily: AppTheme.fontBody,
                              fontSize: 14,
                              color: _currentSort == opt
                                  ? AppTheme.primary
                                  : AppTheme.textPrimary,
                              fontWeight: _currentSort == opt
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                          if (_currentSort == opt) ...[
                            const Spacer(),
                            const Icon(
                              Icons.check,
                              size: 16,
                              color: AppTheme.primary,
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),

            // Import
            _IconButton(
              icon: Icons.download_outlined,
              onTap: _showImportDialog,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Stats Dashboard ───────────────────────────────────────────────

  Widget _buildStatsDashboard() {
    final stats = _globalStats!;
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: AppTheme.glassGradient,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppTheme.primary.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Column(
          children: [
            // Stats grid
            Row(
              children: [
                _StatCard(
                  label: 'Projects',
                  value: '${stats.totalProjects}',
                  icon: Icons.folder_outlined,
                  iconColor: AppTheme.primary,
                ),
                const SizedBox(width: 10),
                _StatCard(
                  label: 'Files',
                  value: '${stats.totalFiles}',
                  icon: Icons.insert_drive_file_outlined,
                  iconColor: AppTheme.accent,
                ),
                const SizedBox(width: 10),
                _StatCard(
                  label: 'Lines',
                  value: _formatCompactNumber(stats.totalLinesOfCode),
                  icon: Icons.code,
                  iconColor: const Color(0xFFF59E0B),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Language distribution
            if (stats.languageDistribution.isNotEmpty)
              _buildLanguageDistribution(stats),

            const SizedBox(height: 10),

            // Streak and active project
            Row(
              children: [
                Icon(
                  Icons.local_fire_department,
                  size: 16,
                  color: stats.currentStreakDays > 0
                      ? Colors.orange
                      : AppTheme.textTertiary,
                ),
                const SizedBox(width: 6),
                Text(
                  '${stats.currentStreakDays} day streak',
                  style: TextStyle(
                    fontFamily: AppTheme.fontBody,
                    fontSize: 12,
                    color: stats.currentStreakDays > 0
                        ? const Color(0xFFF59E0B)
                        : AppTheme.textTertiary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                if (stats.mostActiveProject != null)
                  Flexible(
                    child: Text(
                      'Most active: ${stats.mostActiveProject!.name}',
                      style: const TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 11,
                        color: AppTheme.textTertiary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageDistribution(GlobalStats stats) {
    final percentages = stats.languagePercentages();
    final sortedLangs = percentages.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topLangs = sortedLangs.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Languages',
          style: TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AppTheme.textTertiary,
          ),
        ),
        const SizedBox(height: 6),
        // Horizontal bar chart
        Row(
          children: topLangs.map((entry) {
            final widthFraction = (entry.value / 100).clamp(0.05, 1.0);
            return Flexible(
              flex: (widthFraction * 100).ceil(),
              child: Container(
                height: 6,
                margin: const EdgeInsets.only(right: 2),
                decoration: BoxDecoration(
                  color: _languageColor(entry.key),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 6),
        // Legend
        Wrap(
          spacing: 12,
          children: topLangs.map((entry) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: _languageColor(entry.key),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '${_languageDisplayName(entry.key)} ${entry.value.toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontFamily: AppTheme.fontBody,
                    fontSize: 10,
                    color: AppTheme.textTertiary,
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }

  // ─── Search & Filters ──────────────────────────────────────────────

  Widget _buildSearchAndFilters() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceInput,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isSearching
                  ? AppTheme.borderActive
                  : AppTheme.border,
              width: 1,
            ),
          ),
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            style: const TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 15,
              color: AppTheme.textPrimary,
            ),
            onTap: () => setState(() => _isSearching = true),
            onSubmitted: (_) => setState(() => _isSearching = false),
            decoration: InputDecoration(
              hintText: 'Search projects...',
              hintStyle: const TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 15,
                color: AppTheme.textTertiary,
              ),
              prefixIcon: const Icon(
                Icons.search,
                color: AppTheme.textTertiary,
                size: 20,
              ),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(
                        Icons.clear,
                        color: AppTheme.textTertiary,
                        size: 18,
                      ),
                      onPressed: () {
                        _searchController.clear();
                        _searchFocusNode.unfocus();
                        setState(() => _isSearching = false);
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Category Tabs ─────────────────────────────────────────────────

  Widget _buildCategoryTabs() {
    final categories = [
      ProjectCategory.all,
      ProjectCategory.work,
      ProjectCategory.personal,
      ProjectCategory.learning,
      ProjectCategory.archive,
    ];

    return SliverToBoxAdapter(
      child: Container(
        height: 40,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: categories.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final cat = categories[index];
            final isActive = _currentCategory == cat;

            return GestureDetector(
              onTap: () => _filterByCategory(cat),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppTheme.primary.withOpacity(0.15)
                      : AppTheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isActive
                        ? AppTheme.primary.withOpacity(0.4)
                        : AppTheme.border,
                    width: 1,
                  ),
                ),
                child: Text(
                  ProjectCategory.labels[cat] ?? cat,
                  style: TextStyle(
                    fontFamily: AppTheme.fontBody,
                    fontSize: 13,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                    color: isActive ? AppTheme.primary : AppTheme.textSecondary,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ─── Loading State ─────────────────────────────────────────────────

  Widget _buildLoading() {
    return SliverFillRemaining(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation(
                  AppTheme.primary.withOpacity(0.8),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Loading projects...',
              style: TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 14,
                color: AppTheme.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Project Grid ──────────────────────────────────────────────────

  Widget _buildProjectGrid() {
    if (_filteredProjects.isEmpty) {
      return _buildEmptyState();
    }

    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 320,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: 1.35,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final project = _filteredProjects[index];
            return _buildProjectCard(project);
          },
          childCount: _filteredProjects.length,
        ),
      ),
    );
  }

  Widget _buildProjectCard(Project project) {
    // Calculate line count for display.
    int lineCount = 0;
    void countLines(List<FileItem> files) {
      for (final f in files) {
        if (f.isDirectory && f.children != null) {
          countLines(f.children!);
        } else if (f.content != null) {
          lineCount += f.content!.split('\n').length;
        }
      }
    }
    countLines(project.files);

    return ProjectCardWidget(
      name: project.name,
      description: project.description.isNotEmpty ? project.description : null,
      language: project.language,
      fileCount: project.fileCount,
      lineCount: lineCount,
      isFavorite: project.isFavorite,
      modifiedAt: project.updatedAt,
      onTap: () => _openProject(project),
      onFavoriteToggle: () => _toggleFavorite(project.id),
      onLongPress: () => _showProjectActions(project),
    );
  }

  // ─── Empty State ───────────────────────────────────────────────────

  Widget _buildEmptyState() {
    final isSearching = _searchController.text.isNotEmpty;
    final isArchive = _currentCategory == ProjectCategory.archive;

    return SliverFillRemaining(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSearching
                    ? Icons.search_off
                    : isArchive
                        ? Icons.archive_outlined
                        : Icons.folder_open_outlined,
                size: 56,
                color: AppTheme.textTertiary.withOpacity(0.3),
              ),
              const SizedBox(height: 16),
              Text(
                isSearching
                    ? 'No projects match your search'
                    : isArchive
                        ? 'No archived projects'
                        : AppStrings.projectEmpty,
                style: const TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                isSearching
                    ? 'Try different keywords'
                    : isArchive
                        ? 'Archive projects to see them here'
                        : 'Tap + to create your first project',
                style: TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 13,
                  color: AppTheme.textTertiary.withOpacity(0.7),
                ),
                textAlign: TextAlign.center,
              ),
              if (!isSearching && !isArchive) ...[
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _showCreateProjectDialog,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Create Project'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: AppTheme.textOnPrimary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ─── FAB ───────────────────────────────────────────────────────────

  Widget _buildFAB() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Secondary FAB for quick import
        FloatingActionButton.small(
          heroTag: 'import_fab',
          onPressed: _showImportDialog,
          backgroundColor: AppTheme.surfaceHover,
          foregroundColor: AppTheme.textSecondary,
          elevation: 0,
          child: const Icon(Icons.download, size: 20),
        ),
        const SizedBox(height: 8),
        // Primary FAB for new project
        FloatingActionButton.extended(
          heroTag: 'create_fab',
          onPressed: _showCreateProjectDialog,
          backgroundColor: AppTheme.primary,
          foregroundColor: AppTheme.textOnPrimary,
          elevation: 2,
          icon: const Icon(Icons.add),
          label: const Text(
            'New Project',
            style: TextStyle(
              fontFamily: AppTheme.fontBody,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  // ─── Actions ───────────────────────────────────────────────────────

  void _openProject(Project project) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProjectDetailScreen(
          projectName: project.name,
          language: project.language,
        ),
      ),
    );
  }

  Future<void> _toggleFavorite(String id) async {
    await _projectManager.toggleFavorite(id);
    _loadProjects();
  }

  // ─── Create Project Dialog ─────────────────────────────────────────

  void _showCreateProjectDialog() {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    String selectedTemplate = 'empty';
    String selectedLanguage = 'text';
    int selectedColor = AppTheme.primary.value;

    final colorOptions = [
      AppTheme.primary,
      AppTheme.accent,
      const Color(0xFFF59E0B),
      const Color(0xFFEF4444),
      const Color(0xFF3B82F6),
      const Color(0xFFEC4899),
      const Color(0xFF10B981),
      const Color(0xFF8B5CF6),
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return DraggableScrollableSheet(
            initialChildSize: 0.85,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder: (context, scrollController) {
              return Container(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle
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

                    // Title
                    const Text(
                      'Create New Project',
                      style: TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Choose a template or start from scratch',
                      style: TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 13,
                        color: AppTheme.textTertiary.withOpacity(0.8),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Scrollable content
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        children: [
                          // Project name
                          _buildLabel('Project Name'),
                          const SizedBox(height: 8),
                          TextField(
                            controller: nameController,
                            autofocus: true,
                            style: const TextStyle(
                              fontFamily: AppTheme.fontBody,
                              color: AppTheme.textPrimary,
                            ),
                            decoration: InputDecoration(
                              hintText: 'My Awesome Project',
                              hintStyle: TextStyle(
                                fontFamily: AppTheme.fontBody,
                                color: AppTheme.textTertiary.withOpacity(0.5),
                              ),
                              filled: true,
                              fillColor: AppTheme.surfaceInput,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                  color: AppTheme.border,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                  color: AppTheme.primary,
                                  width: 1.5,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Description
                          _buildLabel('Description (Optional)'),
                          const SizedBox(height: 8),
                          TextField(
                            controller: descController,
                            style: const TextStyle(
                              fontFamily: AppTheme.fontBody,
                              color: AppTheme.textPrimary,
                            ),
                            maxLines: 2,
                            decoration: InputDecoration(
                              hintText: 'A short description...',
                              hintStyle: TextStyle(
                                fontFamily: AppTheme.fontBody,
                                color: AppTheme.textTertiary.withOpacity(0.5),
                              ),
                              filled: true,
                              fillColor: AppTheme.surfaceInput,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                  color: AppTheme.border,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                  color: AppTheme.primary,
                                  width: 1.5,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Color picker
                          _buildLabel('Project Color'),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            children: colorOptions.map((color) {
                              final isSelected = selectedColor == color.value;
                              return GestureDetector(
                                onTap: () => setModalState(
                                  () => selectedColor = color.value,
                                ),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.transparent,
                                      width: 2.5,
                                    ),
                                    boxShadow: isSelected
                                        ? [
                                            BoxShadow(
                                              color: color.withOpacity(0.4),
                                              blurRadius: 8,
                                              spreadRadius: 1,
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: isSelected
                                      ? const Icon(
                                          Icons.check,
                                          color: Colors.white,
                                          size: 16,
                                        )
                                      : null,
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 24),

                          // Templates
                          _buildLabel('Template'),
                          const SizedBox(height: 12),
                          ...ProjectManager.templates.entries.map((entry) {
                            final key = entry.key;
                            final data = entry.value;
                            final isSelected = selectedTemplate == key;
                            final lang = data['language'] as String;

                            return GestureDetector(
                              onTap: () => setModalState(() {
                                selectedTemplate = key;
                                selectedLanguage = lang;
                              }),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppTheme.primary.withOpacity(0.08)
                                      : AppTheme.surface,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected
                                        ? AppTheme.primary.withOpacity(0.4)
                                        : AppTheme.border,
                                    width: isSelected ? 1.5 : 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: _languageColor(lang)
                                            .withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(
                                        _templateIcon(key),
                                        color: _languageColor(lang),
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            data['label'] as String,
                                            style: TextStyle(
                                              fontFamily: AppTheme.fontBody,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: isSelected
                                                  ? AppTheme.textPrimary
                                                  : AppTheme.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            data['description'] as String,
                                            style: const TextStyle(
                                              fontFamily: AppTheme.fontBody,
                                              fontSize: 12,
                                              color: AppTheme.textTertiary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isSelected)
                                      const Icon(
                                        Icons.check_circle,
                                        color: AppTheme.primary,
                                        size: 22,
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),

                    // Create button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          if (nameController.text.trim().isEmpty) {
                            _showError('Please enter a project name');
                            return;
                          }
                          Navigator.pop(context);
                          await _projectManager.createProject(
                            nameController.text.trim(),
                            selectedLanguage == 'text'
                                ? 'markdown'
                                : selectedLanguage,
                            description: descController.text.trim(),
                            template: selectedTemplate,
                            colorCode: selectedColor,
                          );
                          _loadProjects();
                          _showSuccess(
                            'Project "${nameController.text.trim()}" created',
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: AppTheme.textOnPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Create Project',
                          style: TextStyle(
                            fontFamily: AppTheme.fontBody,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ─── Import Dialog ─────────────────────────────────────────────────

  void _showImportDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
              'Import Project',
              style: TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose an import source',
              style: TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 13,
                color: AppTheme.textTertiary.withOpacity(0.8),
              ),
            ),
            const SizedBox(height: 20),

            // Import from ZIP
            _ImportOptionTile(
              icon: Icons.folder_zip_outlined,
              iconColor: const Color(0xFFF59E0B),
              title: 'Import from ZIP',
              subtitle: 'Select a .zip file from your device',
              onTap: () {
                Navigator.pop(context);
                _importFromZip();
              },
            ),
            const SizedBox(height: 10),

            // Import from GitHub
            _ImportOptionTile(
              icon: Icons.code,
              iconColor: const Color(0xFF10B981),
              title: 'Import from GitHub',
              subtitle: 'Clone a repository by URL',
              onTap: () {
                Navigator.pop(context);
                _showGitHubImportDialog();
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _importFromZip() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );

      if (result != null && result.files.single.path != null) {
        setState(() => _isLoading = true);
        final project = await _projectManager.importFromZip(
          result.files.single.path!,
        );
        await _loadProjects();
        _showSuccess('Imported "${project.name}" from ZIP');
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Import failed: $e');
    }
  }

  void _showGitHubImportDialog() {
    final urlController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.border),
        ),
        title: const Text(
          'Import from GitHub',
          style: TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter a GitHub repository URL:',
              style: TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 13,
                color: AppTheme.textTertiary.withOpacity(0.8),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlController,
              autofocus: true,
              style: const TextStyle(
                fontFamily: AppTheme.fontBody,
                color: AppTheme.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'https://github.com/owner/repo',
                hintStyle: TextStyle(
                  fontFamily: AppTheme.fontBody,
                  color: AppTheme.textTertiary.withOpacity(0.5),
                ),
                filled: true,
                fillColor: AppTheme.surfaceInput,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppTheme.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: AppTheme.primary,
                    width: 1.5,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              AppStrings.cancel,
              style: TextStyle(
                fontFamily: AppTheme.fontBody,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              if (urlController.text.trim().isEmpty) {
                _showError('Please enter a URL');
                return;
              }
              Navigator.pop(context);
              setState(() => _isLoading = true);
              try {
                final project = await _projectManager.importFromGitHub(
                  urlController.text.trim(),
                );
                await _loadProjects();
                _showSuccess('Imported "${project.name}" from GitHub');
              } catch (e) {
                setState(() => _isLoading = false);
                _showError('GitHub import failed: $e');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: AppTheme.textOnPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
            child: const Text(
              'Import',
              style: TextStyle(fontFamily: AppTheme.fontBody),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Project Actions Bottom Sheet ──────────────────────────────────

  void _showProjectActions(Project project) {
    final isArchived = _currentCategory == ProjectCategory.archive;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
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
              const SizedBox(height: 16),

              // Project info header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: _languageColor(project.language).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          project.name.isNotEmpty
                              ? project.name[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            fontFamily: AppTheme.fontBody,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _languageColor(project.language),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            project.name,
                            style: const TextStyle(
                              fontFamily: AppTheme.fontBody,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${project.language.toUpperCase()}  \u2022  ${project.fileCount} files',
                            style: const TextStyle(
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
              ),

              const SizedBox(height: 16),
              const Divider(color: AppTheme.divider, indent: 24, endIndent: 24),

              // Actions
              _ActionTile(
                icon: Icons.open_in_new,
                iconColor: AppTheme.accent,
                title: 'Open in Editor',
                onTap: () {
                  Navigator.pop(context);
                  _openProject(project);
                },
              ),
              _ActionTile(
                icon: Icons.edit_outlined,
                iconColor: AppTheme.textSecondary,
                title: AppStrings.projectRename,
                onTap: () {
                  Navigator.pop(context);
                  _showRenameDialog(project);
                },
              ),
              _ActionTile(
                icon: Icons.content_copy_outlined,
                iconColor: AppTheme.textSecondary,
                title: AppStrings.projectDuplicate,
                onTap: () async {
                  Navigator.pop(context);
                  setState(() => _isLoading = true);
                  await _projectManager.duplicateProject(project.id);
                  await _loadProjects();
                  _showSuccess('Project duplicated');
                },
              ),
              _ActionTile(
                icon: Icons.share_outlined,
                iconColor: AppTheme.textSecondary,
                title: 'Export as ZIP',
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    final path = await _projectManager.exportToZip(project.id);
                    _showSuccess('Exported to $path');
                  } catch (e) {
                    _showError('Export failed: $e');
                  }
                },
              ),

              // Git actions
              _ActionTile(
                icon: Icons.commit_outlined,
                iconColor: const Color(0xFFF59E0B),
                title: 'Git: Quick Commit',
                onTap: () {
                  Navigator.pop(context);
                  _showGitCommitDialog(project);
                },
              ),

              const Divider(color: AppTheme.divider, indent: 24, endIndent: 24),

              if (isArchived)
                _ActionTile(
                  icon: Icons.unarchive_outlined,
                  iconColor: AppTheme.accent,
                  title: 'Unarchive',
                  onTap: () async {
                    Navigator.pop(context);
                    await _projectManager.unarchiveProject(project.id);
                    _loadProjects();
                    _showSuccess('Project unarchived');
                  },
                )
              else
                _ActionTile(
                  icon: Icons.archive_outlined,
                  iconColor: AppTheme.warning,
                  title: 'Archive',
                  onTap: () async {
                    Navigator.pop(context);
                    await _projectManager.archiveProject(project.id);
                    _loadProjects();
                    _showSuccess('Project archived');
                  },
                ),
              _ActionTile(
                icon: Icons.delete_outline,
                iconColor: AppTheme.error,
                title: AppStrings.delete,
                onTap: () {
                  Navigator.pop(context);
                  _showDeleteConfirm(project);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Dialogs ───────────────────────────────────────────────────────

  void _showRenameDialog(Project project) {
    final controller = TextEditingController(text: project.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.border),
        ),
        title: const Text(
          'Rename Project',
          style: TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(
            fontFamily: AppTheme.fontBody,
            color: AppTheme.textPrimary,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppTheme.surfaceInput,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: AppTheme.primary,
                width: 1.5,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              AppStrings.cancel,
              style: TextStyle(
                fontFamily: AppTheme.fontBody,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context);
                await _projectManager.renameProject(
                  project.id,
                  controller.text.trim(),
                );
                _loadProjects();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: AppTheme.textOnPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
            child: const Text(
              'Rename',
              style: TextStyle(fontFamily: AppTheme.fontBody),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirm(Project project) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.border),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.error),
            SizedBox(width: 10),
            Text(
              'Delete Project',
              style: TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to permanently delete "${project.name}"? This action cannot be undone.',
          style: const TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 14,
            color: AppTheme.textSecondary,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              AppStrings.cancel,
              style: TextStyle(
                fontFamily: AppTheme.fontBody,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              setState(() => _isLoading = true);
              await _projectManager.deleteProject(project.id);
              await _loadProjects();
              _showSuccess('Project deleted');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
            child: const Text(
              AppStrings.delete,
              style: TextStyle(fontFamily: AppTheme.fontBody),
            ),
          ),
        ],
      ),
    );
  }

  void _showGitCommitDialog(Project project) {
    final messageController = TextEditingController(
      text: 'Update ${project.name}',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.border),
        ),
        title: const Text(
          'Quick Commit',
          style: TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: messageController,
              autofocus: true,
              style: const TextStyle(
                fontFamily: AppTheme.fontBody,
                color: AppTheme.textPrimary,
              ),
              decoration: InputDecoration(
                labelText: 'Commit message',
                labelStyle: const TextStyle(
                  fontFamily: AppTheme.fontBody,
                  color: AppTheme.textSecondary,
                ),
                filled: true,
                fillColor: AppTheme.surfaceInput,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppTheme.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: AppTheme.primary,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              AppStrings.cancel,
              style: TextStyle(
                fontFamily: AppTheme.fontBody,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _projectManager.quickCommit(
                project.id,
                messageController.text,
              );
              _showSuccess('Committed changes');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
            child: const Text(
              'Commit',
              style: TextStyle(fontFamily: AppTheme.fontBody),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Helper Methods ────────────────────────────────────────────────

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: AppTheme.error, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.surfaceHover,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppTheme.border),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline,
                color: AppTheme.accent, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.surfaceHover,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppTheme.border),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: AppTheme.fontBody,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppTheme.textSecondary,
        letterSpacing: 0.3,
      ),
    );
  }

  // ─── Utility Helpers ───────────────────────────────────────────────

  Color _languageColor(String language) {
    final colors = {
      'dart': const Color(0xFF00B4AB),
      'python': const Color(0xFF3776AB),
      'javascript': const Color(0xFFF7DF1E),
      'typescript': const Color(0xFF3178C6),
      'go': const Color(0xFF00ADD8),
      'rust': const Color(0xFFDEA584),
      'swift': const Color(0xFFFFAC45),
      'kotlin': const Color(0xFF7F52FF),
      'java': const Color(0xFF007396),
      'cpp': const Color(0xFF00599C),
      'c': const Color(0xFF555555),
      'csharp': const Color(0xFF68217A),
      'ruby': const Color(0xFFCC342D),
      'php': const Color(0xFF4F5D95),
      'html': const Color(0xFFE34F26),
      'css': const Color(0xFF1572B6),
      'markdown': const Color(0xFF083FA1),
      'yaml': const Color(0xFFCB171E),
      'json': const Color(0xFFF9D423),
      'text': AppTheme.textSecondary,
    };
    return colors[language.toLowerCase()] ?? AppTheme.textSecondary;
  }

  String _languageDisplayName(String language) {
    return SupportedLanguages.languages[language.toLowerCase()] ??
        language.toUpperCase();
  }

  IconData _templateIcon(String templateKey) {
    final icons = {
      'flutter': Icons.flutter_dash,
      'python': Icons.terminal,
      'go': Icons.memory,
      'web': Icons.web,
      'react': Icons.javascript,
      'empty': Icons.folder_open_outlined,
    };
    return icons[templateKey] ?? Icons.folder_outlined;
  }

  String _formatCompactNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Supporting Widgets
// ═══════════════════════════════════════════════════════════════════════════

class _IconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isActive;

  const _IconButton({
    required this.icon,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isActive
                ? AppTheme.primary.withOpacity(0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 22,
            color: isActive ? AppTheme.primary : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppTheme.border.withOpacity(0.4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
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
        ),
      ),
    );
  }
}

class _ImportOptionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ImportOptionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppTheme.border.withOpacity(0.5),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 12,
                      color: AppTheme.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: AppTheme.textTertiary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 22),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 15,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
