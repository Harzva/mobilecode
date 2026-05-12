import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../services/github_deep_service.dart';
import '../services/github_gist_service.dart';

// =============================================================================
// GITHUB GIST SCREEN
// =============================================================================

/// Tabbed Gist browser and editor for MobileCode.
///
/// Three tabs:
/// - **My Gists**: Current user's gists with edit/delete actions
/// - **Starred**: Gists the user has starred
/// - **Discover**: Public gists from the GitHub community
///
/// Supports creating, editing, viewing, starring, forking, and sharing gists.
class GitHubGistScreen extends StatefulWidget {
  const GitHubGistScreen({super.key});

  @override
  State<GitHubGistScreen> createState() => _GitHubGistScreenState();
}

class _GitHubGistScreenState extends State<GitHubGistScreen>
    with TickerProviderStateMixin {
  late final TabController _tabController;
  final _searchController = TextEditingController();

  GitHubGistService? _gistService;
  List<Gist> _myGists = [];
  List<Gist> _starredGists = [];
  List<Gist> _publicGists = [];
  bool _isLoading = true;
  String? _error;
  int _currentPage = 1;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    _initialize();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _gistService?.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    // The gist service will be provided by the caller via context or
    // we create it from the available GitHubDeepService.
    // For now, schedule the load after first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) {
      setState(() {});
    }
  }

  /// Set the GitHub service from the parent. Call this before loading.
  void setGitHubService(GitHubDeepService github) {
    _gistService = GitHubGistService(github);
  }

  Future<void> _loadData() async {
    if (_gistService == null) {
      setState(() {
        _isLoading = false;
        _error = 'GitHub service not initialized';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _gistService!.listGists(),
        _gistService!.listStarredGists(),
        _gistService!.listPublicGists(),
      ]);

      setState(() {
        _myGists = results[0];
        _starredGists = results[1];
        _publicGists = results[2];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_gistService == null || _isLoading) return;
    setState(() => _isLoading = true);
    _currentPage++;

    try {
      switch (_tabController.index) {
        case 0:
          final more = await _gistService!.listGists(page: _currentPage);
          setState(() => _myGists.addAll(more));
        case 1:
          final more = await _gistService!.listStarredGists(page: _currentPage);
          setState(() => _starredGists.addAll(more));
        case 2:
          final more = await _gistService!.listPublicGists(page: _currentPage);
          setState(() => _publicGists.addAll(more));
      }
    } catch (e) {
      // Silently fail on pagination errors.
      debugPrint('Failed to load more gists: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ── Gist Actions ────────────────────────────────────────────────────

  Future<void> _deleteGist(Gist gist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Delete Gist', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text(
          'Are you sure you want to delete "${gist.description}"? This cannot be undone.',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );

    if (confirmed != true || _gistService == null) return;

    try {
      await _gistService!.deleteGist(gist.id);
      setState(() => _myGists.removeWhere((g) => g.id == gist.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gist deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
        );
      }
    }
  }

  Future<void> _toggleStar(Gist gist) async {
    if (_gistService == null) return;
    try {
      final isStarred = await _gistService!.isGistStarred(gist.id);
      if (isStarred) {
        await _gistService!.unstarGist(gist.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Unstarred')),
          );
        }
      } else {
        await _gistService!.starGist(gist.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Starred')),
          );
        }
      }
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  Future<void> _forkGist(Gist gist) async {
    if (_gistService == null) return;
    try {
      final forked = await _gistService!.forkGist(gist.id);
      setState(() => _myGists.insert(0, forked));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Forked to ${forked.htmlUrl}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to fork: $e')),
        );
      }
    }
  }

  void _shareGist(Gist gist) {
    _copyToClipboard(gist.htmlUrl, 'Gist URL copied');
  }

  void _copyEmbedCode(Gist gist) {
    final embed = '<script src="${gist.embedUrl}"></script>';
    _copyToClipboard(embed, 'Embed code copied');
  }

  void _copyToClipboard(String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _openGistEditor({Gist? gist}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _GistEditorScreen(
          gistService: _gistService,
          gist: gist,
          onSaved: _loadData,
        ),
      ),
    );
  }

  void _openGistDetail(Gist gist) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _GistDetailScreen(
          gistService: _gistService,
          gist: gist,
          onStarToggled: _loadData,
        ),
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('GitHub Gists'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.code), text: 'My Gists'),
            Tab(icon: Icon(Icons.star_border), text: 'Starred'),
            Tab(icon: Icon(Icons.explore), text: 'Discover'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _gistService == null
          ? const Center(
              child: Text(
                'GitHub not connected',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _GistListView(
                        gists: _myGists,
                        isLoading: _isLoading,
                        error: _error,
                        onRefresh: _loadData,
                        onLoadMore: _loadMore,
                        onTap: _openGistDetail,
                        onDelete: _deleteGist,
                        onStar: _toggleStar,
                        onFork: _forkGist,
                        onShare: _shareGist,
                        onCopyEmbed: _copyEmbedCode,
                        isOwnerView: true,
                      ),
                      _GistListView(
                        gists: _starredGists,
                        isLoading: _isLoading,
                        error: _error,
                        onRefresh: _loadData,
                        onLoadMore: _loadMore,
                        onTap: _openGistDetail,
                        onStar: _toggleStar,
                        onFork: _forkGist,
                        onShare: _shareGist,
                        onCopyEmbed: _copyEmbedCode,
                      ),
                      _GistListView(
                        gists: _publicGists,
                        isLoading: _isLoading,
                        error: _error,
                        onRefresh: _loadData,
                        onLoadMore: _loadMore,
                        onTap: _openGistDetail,
                        onStar: _toggleStar,
                        onFork: _forkGist,
                        onShare: _shareGist,
                        onCopyEmbed: _copyEmbedCode,
                      ),
                    ],
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openGistEditor(),
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.add, color: AppTheme.textOnPrimary),
        label: const Text(
          'New Gist',
          style: TextStyle(color: AppTheme.textOnPrimary),
        ),
      ),
    );
  }
}

// =============================================================================
// GIST LIST VIEW
// =============================================================================

class _GistListView extends StatelessWidget {
  final List<Gist> gists;
  final bool isLoading;
  final String? error;
  final VoidCallback onRefresh;
  final VoidCallback onLoadMore;
  final ValueChanged<Gist> onTap;
  final ValueChanged<Gist>? onDelete;
  final ValueChanged<Gist>? onStar;
  final ValueChanged<Gist>? onFork;
  final ValueChanged<Gist>? onShare;
  final ValueChanged<Gist>? onCopyEmbed;
  final bool isOwnerView;

  const _GistListView({
    required this.gists,
    required this.isLoading,
    required this.error,
    required this.onRefresh,
    required this.onLoadMore,
    required this.onTap,
    this.onDelete,
    this.onStar,
    this.onFork,
    this.onShare,
    this.onCopyEmbed,
    this.isOwnerView = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading && gists.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    if (error != null && gists.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppTheme.error, size: 48),
            const SizedBox(height: 12),
            Text(
              'Error loading gists',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: onRefresh,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (gists.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.code_off, color: AppTheme.textTertiary, size: 48),
            SizedBox(height: 12),
            Text(
              'No gists found',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      color: AppTheme.primary,
      backgroundColor: AppTheme.surface,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: gists.length + (isLoading ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= gists.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: AppTheme.primary,
                    strokeWidth: 2,
                  ),
                ),
              ),
            );
          }

          final gist = gists[index];
          return _GistCard(
            gist: gist,
            onTap: () => onTap(gist),
            onDelete: isOwnerView ? () => onDelete?.call(gist) : null,
            onStar: () => onStar?.call(gist),
            onFork: () => onFork?.call(gist),
            onShare: () => onShare?.call(gist),
            onCopyEmbed: () => onCopyEmbed?.call(gist),
          );
        },
      ),
    );
  }
}

// =============================================================================
// GIST CARD
// =============================================================================

class _GistCard extends StatelessWidget {
  final Gist gist;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onStar;
  final VoidCallback? onFork;
  final VoidCallback? onShare;
  final VoidCallback? onCopyEmbed;

  const _GistCard({
    required this.gist,
    required this.onTap,
    this.onDelete,
    this.onStar,
    this.onFork,
    this.onShare,
    this.onCopyEmbed,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppTheme.surface,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppTheme.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: description + menu.
              Row(
                children: [
                  Expanded(
                    child: Text(
                      gist.description.isNotEmpty
                          ? gist.description
                          : gist.firstFileName ?? 'Untitled Gist',
                      style: const TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _buildPopupMenu(),
                ],
              ),
              const SizedBox(height: 8),
              // File chips.
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: gist.files.values.map((file) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceHover,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Text(
                      file.displayName,
                      style: const TextStyle(
                        fontFamily: AppTheme.fontCode,
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              // Footer: language + files count + comments + date.
              Row(
                children: [
                  if (gist.firstFileLanguage != null) ...[
                    _LanguageDot(language: gist.firstFileLanguage!),
                    const SizedBox(width: 4),
                    Text(
                      gist.firstFileLanguage!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Icon(
                    Icons.insert_drive_file_outlined,
                    size: 14,
                    color: AppTheme.textTertiary.withOpacity(0.7),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '${gist.fileCount}',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textTertiary),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    Icons.comment_outlined,
                    size: 14,
                    color: AppTheme.textTertiary.withOpacity(0.7),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '${gist.comments}',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textTertiary),
                  ),
                  const Spacer(),
                  Text(
                    _formatDate(gist.updatedAt),
                    style: const TextStyle(fontSize: 11, color: AppTheme.textTertiary),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPopupMenu() {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: AppTheme.textTertiary, size: 20),
      color: AppTheme.surfaceHover,
      onSelected: (value) {
        switch (value) {
          case 'star':
            onStar?.call();
          case 'fork':
            onFork?.call();
          case 'share':
            onShare?.call();
          case 'embed':
            onCopyEmbed?.call();
          case 'delete':
            onDelete?.call();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(value: 'star', child: _menuItem(Icons.star_border, 'Star / Unstar')),
        PopupMenuItem(value: 'fork', child: _menuItem(Icons.fork_right, 'Fork')),
        PopupMenuItem(value: 'share', child: _menuItem(Icons.share, 'Copy URL')),
        PopupMenuItem(value: 'embed', child: _menuItem(Icons.code, 'Copy Embed')),
        if (onDelete != null)
          PopupMenuItem(
            value: 'delete',
            child: _menuItem(Icons.delete_outline, 'Delete', color: AppTheme.error),
          ),
      ],
    );
  }

  Widget _menuItem(IconData icon, String label, {Color? color}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color ?? AppTheme.textSecondary),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 14,
            color: color ?? AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  static String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays > 365) return '${(diff.inDays / 365).floor()}y ago';
    if (diff.inDays > 30) return '${(diff.inDays / 30).floor()}mo ago';
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'just now';
  }
}

// =============================================================================
// LANGUAGE DOT
// =============================================================================

class _LanguageDot extends StatelessWidget {
  final String language;

  const _LanguageDot({required this.language});

  static final Map<String, Color> _languageColors = {
    'Dart': const Color(0xFF00B4AB),
    'JavaScript': const Color(0xFFF1E05A),
    'TypeScript': const Color(0xFF3178C6),
    'Python': const Color(0xFF3572A5),
    'Java': const Color(0xFFB07219),
    'Go': const Color(0xFF00ADD8),
    'Rust': const Color(0xFFDEA584),
    'C++': const Color(0xFFF34B7D),
    'C': const Color(0xFF555555),
    'Swift': const Color(0xFFFFAC45),
    'Kotlin': const Color(0xFFA97BFF),
    'Ruby': const Color(0xFF701516),
    'PHP': const Color(0xFF4F5D95),
    'HTML': const Color(0xFFE34C26),
    'CSS': const Color(0xFF563D7C),
    'Shell': const Color(0xFF89E051),
    'JSON': const Color(0xFF292929),
    'YAML': const Color(0xFFCB171E),
    'Markdown': const Color(0xFF083FA1),
  };

  @override
  Widget build(BuildContext context) {
    final color = _languageColors[language] ?? AppTheme.accent;
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

// =============================================================================
// GIST DETAIL SCREEN
// =============================================================================

class _GistDetailScreen extends StatefulWidget {
  final GitHubGistService? gistService;
  final Gist gist;
  final VoidCallback? onStarToggled;

  const _GistDetailScreen({
    required this.gistService,
    required this.gist,
    this.onStarToggled,
  });

  @override
  State<_GistDetailScreen> createState() => _GistDetailScreenState();
}

class _GistDetailScreenState extends State<_GistDetailScreen> {
  Gist? _fullGist;
  bool _isLoading = true;
  String _selectedFile = '';

  @override
  void initState() {
    super.initState();
    _loadGist();
  }

  Future<void> _loadGist() async {
    if (widget.gistService == null) {
      setState(() {
        _fullGist = widget.gist;
        _isLoading = false;
        _selectedFile = widget.gist.firstFileName ?? '';
      });
      return;
    }

    try {
      final gist = await widget.gistService!.getGist(widget.gist.id);
      setState(() {
        _fullGist = gist;
        _selectedFile = gist.firstFileName ?? '';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _fullGist = widget.gist;
        _selectedFile = widget.gist.firstFileName ?? '';
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleStar() async {
    if (widget.gistService == null) return;
    try {
      final isStarred = await widget.gistService!.isGistStarred(widget.gist.id);
      if (isStarred) {
        await widget.gistService!.unstarGist(widget.gist.id);
      } else {
        await widget.gistService!.starGist(widget.gist.id);
      }
      widget.onStarToggled?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isStarred ? 'Unstarred' : 'Starred')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final gist = _fullGist ?? widget.gist;
    final fileNames = gist.files.keys.toList();
    final currentFile = gist.files[_selectedFile];

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(
          gist.description.isNotEmpty ? gist.description : 'Gist',
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.star_border),
            onPressed: _toggleStar,
            tooltip: 'Star',
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: gist.htmlUrl));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('URL copied')),
              );
            },
            tooltip: 'Copy URL',
          ),
        ],
      ),
      body: Column(
        children: [
          // File tabs.
          if (fileNames.length > 1)
            Container(
              height: 44,
              color: AppTheme.backgroundElevated,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: fileNames.length,
                itemBuilder: (context, index) {
                  final name = fileNames[index];
                  final isSelected = name == _selectedFile;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: InkWell(
                      onTap: () => setState(() => _selectedFile = name),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected ? AppTheme.primaryMuted : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: isSelected
                              ? const BorderSide(color: AppTheme.primary)
                              : BorderSide(color: AppTheme.border.withOpacity(0.5)),
                        ),
                        child: Text(
                          name,
                          style: TextStyle(
                            fontFamily: AppTheme.fontCode,
                            fontSize: 12,
                            color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          // Code content.
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary),
                  )
                : currentFile?.content != null
                    ? _CodeView(code: currentFile!.content!)
                    : const Center(
                        child: Text(
                          'No content available',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// CODE VIEW (Syntax Highlighted)
// =============================================================================

class _CodeView extends StatelessWidget {
  final String code;

  const _CodeView({required this.code});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.editorBackground,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          code,
          style: const TextStyle(
            fontFamily: AppTheme.fontCode,
            fontSize: 13,
            height: 1.6,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// GIST EDITOR SCREEN
// =============================================================================

class _GistEditorScreen extends StatefulWidget {
  final GitHubGistService? gistService;
  final Gist? gist;
  final VoidCallback? onSaved;

  const _GistEditorScreen({
    required this.gistService,
    this.gist,
    this.onSaved,
  });

  @override
  State<_GistEditorScreen> createState() => _GistEditorScreenState();
}

class _GistEditorScreenState extends State<_GistEditorScreen> {
  late final TextEditingController _descController;
  final List<_FileEditor> _fileEditors = [];
  bool _isPublic = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _descController = TextEditingController(text: widget.gist?.description ?? '');

    if (widget.gist != null && widget.gist!.files.isNotEmpty) {
      for (final entry in widget.gist!.files.entries) {
        _fileEditors.add(_FileEditor(
          nameController: TextEditingController(text: entry.key),
          contentController: TextEditingController(text: entry.value.content ?? ''),
        ));
      }
    } else {
      _addFile();
    }
  }

  @override
  void dispose() {
    _descController.dispose();
    for (final editor in _fileEditors) {
      editor.dispose();
    }
    super.dispose();
  }

  void _addFile() {
    setState(() {
      _fileEditors.add(_FileEditor(
        nameController: TextEditingController(),
        contentController: TextEditingController(),
      ));
    });
  }

  void _removeFile(int index) {
    if (_fileEditors.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A gist must have at least one file')),
      );
      return;
    }
    setState(() {
      _fileEditors[index].dispose();
      _fileEditors.removeAt(index);
    });
  }

  Future<void> _saveGist() async {
    if (widget.gistService == null) return;

    final description = _descController.text.trim();
    if (description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a description')),
      );
      return;
    }

    final files = <String, GistFile>{};
    for (final editor in _fileEditors) {
      final name = editor.nameController.text.trim();
      final content = editor.contentController.text;
      if (name.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All files must have a name')),
        );
        return;
      }
      files[name] = GistFile.withContent(name, content);
    }

    setState(() => _isSaving = true);

    try {
      if (widget.gist != null) {
        // Update existing gist.
        await widget.gistService!.updateGist(
          widget.gist!.id,
          description: description,
          files: files,
        );
      } else {
        // Create new gist.
        await widget.gistService!.createGist(
          description: description,
          files: files,
          isPublic: _isPublic,
        );
      }

      widget.onSaved?.call();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.gist != null ? 'Gist updated' : 'Gist created'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.gist != null;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Gist' : 'New Gist'),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: AppTheme.textOnPrimary,
                  strokeWidth: 2,
                ),
              ),
            )
          else
            TextButton(
              onPressed: _saveGist,
              child: const Text(
                'Save',
                style: TextStyle(
                  color: AppTheme.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Description.
          TextField(
            controller: _descController,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Description',
              hintText: 'Enter gist description...',
            ),
          ),
          const SizedBox(height: 12),
          // Public toggle (only for new gists).
          if (!isEditing)
            Row(
              children: [
                const Text(
                  'Public gist',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                ),
                const SizedBox(width: 8),
                Switch(
                  value: _isPublic,
                  onChanged: (v) => setState(() => _isPublic = v),
                  activeColor: AppTheme.primary,
                ),
                Text(
                  _isPublic ? 'Visible to everyone' : 'Secret (only with link)',
                  style: const TextStyle(color: AppTheme.textTertiary, fontSize: 12),
                ),
              ],
            ),
          const Divider(color: AppTheme.divider, height: 24),
          // Files.
          ..._fileEditors.asMap().entries.expand((entry) {
            final index = entry.key;
            final editor = entry.value;
            return [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: editor.nameController,
                      style: const TextStyle(
                        fontFamily: AppTheme.fontCode,
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Filename',
                        hintText: 'e.g., main.dart',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: AppTheme.error),
                    onPressed: () => _removeFile(index),
                    tooltip: 'Remove file',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.editorBackground,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.border),
                ),
                child: TextField(
                  controller: editor.contentController,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontCode,
                    fontSize: 13,
                    height: 1.6,
                    color: AppTheme.textPrimary,
                  ),
                  maxLines: 12,
                  decoration: const InputDecoration(
                    hintText: 'Paste code here...',
                    contentPadding: EdgeInsets.all(14),
                    border: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ];
          }),
          // Add file button.
          OutlinedButton.icon(
            onPressed: _addFile,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add File'),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// =============================================================================
// FILE EDITOR HELPER
// =============================================================================

class _FileEditor {
  final TextEditingController nameController;
  final TextEditingController contentController;

  _FileEditor({required this.nameController, required this.contentController});

  void dispose() {
    nameController.dispose();
    contentController.dispose();
  }
}
