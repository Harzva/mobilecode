import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme.dart';
import '../services/github_deep_service.dart';
import '../widgets/glass_card_widget.dart';

// ── File Icon Mapper ─────────────────────────────────────────────────────────

final Map<String, IconData> _fileIconMap = {
  '.dart': Icons.flutter_dash,
  '.py': Icons.terminal,
  '.js': Icons.javascript,
  '.ts': Icons.code,
  '.go': Icons.speed,
  '.rs': Icons.memory,
  '.java': Icons.coffee,
  '.cpp': Icons.computer,
  '.c': Icons.computer,
  '.h': Icons.header_outlined,
  '.swift': Icons.apple,
  '.kt': Icons.android,
  '.rb': Icons.diamond,
  '.php': Icons.web,
  '.html': Icons.html,
  '.css': Icons.style,
  '.scss': Icons.style,
  '.json': Icons.data_object,
  '.yaml': Icons.settings,
  '.yml': Icons.settings,
  '.md': Icons.article,
  '.txt': Icons.description,
  '.sh': Icons.terminal,
  '.dockerfile': Icons.cloud,
  '.gitignore': Icons.remove_circle_outline,
  '.toml': Icons.settings,
  '.lock': Icons.lock,
};

final Map<String, Color> _fileIconColors = {
  '.dart': Color(0xFF54C5F8),
  '.py': Color(0xFF3572A5),
  '.js': Color(0xFFF1E05A),
  '.ts': Color(0xFF3178C6),
  '.go': Color(0xFF00ADD8),
  '.rs': Color(0xFFDEA584),
  '.java': Color(0xFFB07219),
  '.swift': Color(0xFFFFAC45),
  '.kt': Color(0xFFA97BFF),
  '.html': Color(0xFFE34C26),
  '.css': Color(0xFF563D7C),
  '.md': Color(0xFF083FA1),
};

// ── File Item Model ──────────────────────────────────────────────────────────

class RepoFileItem {
  final String name;
  final String path;
  final String type; // 'file' | 'dir' | 'symlink'
  final int? size;
  final String? sha;
  final String? htmlUrl;
  final String? downloadUrl;
  final String? gitUrl;
  final DateTime? lastModified;
  final String? content; // decoded content for files

  RepoFileItem({
    required this.name,
    required this.path,
    required this.type,
    this.size,
    this.sha,
    this.htmlUrl,
    this.downloadUrl,
    this.gitUrl,
    this.lastModified,
    this.content,
  });

  factory RepoFileItem.fromGitHubApi(Map<String, dynamic> json) {
    return RepoFileItem(
      name: json['name'] as String? ?? '',
      path: json['path'] as String? ?? '',
      type: json['type'] as String? ?? 'file',
      size: json['size'] as int?,
      sha: json['sha'] as String?,
      htmlUrl: json['html_url'] as String?,
      downloadUrl: json['download_url'] as String?,
      gitUrl: json['git_url'] as String?,
      lastModified: json['last_modified'] != null
          ? DateTime.tryParse(json['last_modified'] as String)
          : null,
    );
  }

  bool get isDirectory => type == 'dir';
  bool get isFile => type == 'file';

  String get extension {
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex > 0) return name.substring(dotIndex);
    return '';
  }

  IconData get icon {
    if (isDirectory) return Icons.folder;
    final ext = extension.toLowerCase();
    return _fileIconMap[ext] ?? Icons.insert_drive_file;
  }

  Color get iconColor {
    if (isDirectory) return AppTheme.warning;
    final ext = extension.toLowerCase();
    return _fileIconColors[ext] ?? AppTheme.textSecondary;
  }

  String get formattedSize {
    if (size == null) return '';
    if (size! >= 1024 * 1024) return '${(size! / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (size! >= 1024) return '${(size! / 1024).toStringAsFixed(1)} KB';
    return '$size B';
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// GITHUB REPO SCREEN — Enhanced Repository Browser
// ═════════════════════════════════════════════════════════════════════════════
/// File browser, README preview, branch selector, repo stats,
/// breadcrumb navigation, and context menus.
class GitHubRepoScreen extends StatefulWidget {
  final String repoName;
  final String owner;
  final String? description;
  final String? language;

  const GitHubRepoScreen({
    super.key,
    required this.repoName,
    required this.owner,
    this.description,
    this.language,
  });

  @override
  State<GitHubRepoScreen> createState() => _GitHubRepoScreenState();
}

class _GitHubRepoScreenState extends State<GitHubRepoScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final GitHubDeepService _svc = GitHubDeepService();

  // File browser state
  List<RepoFileItem> _currentFiles = [];
  final List<String> _pathStack = [];
  String _currentBranch = 'main';
  List<String> _branches = ['main', 'master'];
  RepoFileItem? _selectedFile;
  bool _isEditing = false;
  bool _readmeVisible = true;
  String? _readmeContent;

  // Repo info
  Map<String, dynamic> _repoDetails = {};
  Map<String, dynamic> _languageStats = {};
  bool _loading = true;
  bool _filesLoading = false;
  String? _error;

  // Demo file tree for offline mode
  late List<RepoFileItem> _demoRootFiles;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _currentBranch = widget.language == 'Dart' ? 'main' : 'master';
    _demoRootFiles = _buildDemoFileTree();
    _currentFiles = _demoRootFiles;
    _loadRepoInfo();
    _loadReadme();
  }

  // ── Demo Data ──────────────────────────────────────────────────────────────

  List<RepoFileItem> _buildDemoFileTree() {
    return [
      RepoFileItem(name: 'src', path: 'src', type: 'dir', lastModified: DateTime.now().subtract(const Duration(hours: 2))),
      RepoFileItem(name: 'tests', path: 'tests', type: 'dir', lastModified: DateTime.now().subtract(const Duration(days: 1))),
      RepoFileItem(name: '.github', path: '.github', type: 'dir', lastModified: DateTime.now().subtract(const Duration(days: 3))),
      RepoFileItem(name: 'README.md', path: 'README.md', type: 'file', size: 2450, lastModified: DateTime.now().subtract(const Duration(days: 2))),
      RepoFileItem(name: 'pubspec.yaml', path: 'pubspec.yaml', type: 'file', size: 1200, lastModified: DateTime.now().subtract(const Duration(days: 5))),
      RepoFileItem(name: 'analysis_options.yaml', path: 'analysis_options.yaml', type: 'file', size: 450, lastModified: DateTime.now().subtract(const Duration(days: 7))),
      RepoFileItem(name: '.gitignore', path: '.gitignore', type: 'file', size: 180, lastModified: DateTime.now().subtract(const Duration(days: 10))),
      RepoFileItem(name: 'CHANGELOG.md', path: 'CHANGELOG.md', type: 'file', size: 890, lastModified: DateTime.now().subtract(const Duration(days: 4))),
      RepoFileItem(name: 'LICENSE', path: 'LICENSE', type: 'file', size: 1100, lastModified: DateTime.now().subtract(const Duration(days: 14))),
    ];
  }

  List<RepoFileItem> _buildDemoSubFiles(String path) {
    if (path == 'src') {
      return [
        RepoFileItem(name: 'main.dart', path: 'src/main.dart', type: 'file', size: 3200, lastModified: DateTime.now().subtract(const Duration(hours: 1))),
        RepoFileItem(name: 'app.dart', path: 'src/app.dart', type: 'file', size: 1800, lastModified: DateTime.now().subtract(const Duration(hours: 3))),
        RepoFileItem(name: 'models', path: 'src/models', type: 'dir', lastModified: DateTime.now().subtract(const Duration(hours: 4))),
        RepoFileItem(name: 'screens', path: 'src/screens', type: 'dir', lastModified: DateTime.now().subtract(const Duration(days: 1))),
        RepoFileItem(name: 'widgets', path: 'src/widgets', type: 'dir', lastModified: DateTime.now().subtract(const Duration(days: 1))),
        RepoFileItem(name: 'utils.dart', path: 'src/utils.dart', type: 'file', size: 950, lastModified: DateTime.now().subtract(const Duration(days: 2))),
      ];
    }
    if (path == 'tests') {
      return [
        RepoFileItem(name: 'widget_test.dart', path: 'tests/widget_test.dart', type: 'file', size: 1200, lastModified: DateTime.now().subtract(const Duration(days: 2))),
        RepoFileItem(name: 'unit_test.dart', path: 'tests/unit_test.dart', type: 'file', size: 800, lastModified: DateTime.now().subtract(const Duration(days: 3))),
      ];
    }
    if (path == '.github') {
      return [
        RepoFileItem(name: 'workflows', path: '.github/workflows', type: 'dir', lastModified: DateTime.now().subtract(const Duration(days: 5))),
        RepoFileItem(name: 'ISSUE_TEMPLATE', path: '.github/ISSUE_TEMPLATE', type: 'dir', lastModified: DateTime.now().subtract(const Duration(days: 7))),
      ];
    }
    if (path.endsWith('models')) {
      return [
        RepoFileItem(name: 'user.dart', path: 'src/models/user.dart', type: 'file', size: 650, lastModified: DateTime.now().subtract(const Duration(days: 3))),
        RepoFileItem(name: 'repo.dart', path: 'src/models/repo.dart', type: 'file', size: 720, lastModified: DateTime.now().subtract(const Duration(days: 2))),
      ];
    }
    if (path.endsWith('screens')) {
      return [
        RepoFileItem(name: 'home_screen.dart', path: 'src/screens/home_screen.dart', type: 'file', size: 2100, lastModified: DateTime.now().subtract(const Duration(hours: 5))),
        RepoFileItem(name: 'settings_screen.dart', path: 'src/screens/settings_screen.dart', type: 'file', size: 1500, lastModified: DateTime.now().subtract(const Duration(days: 1))),
      ];
    }
    if (path.endsWith('widgets')) {
      return [
        RepoFileItem(name: 'custom_button.dart', path: 'src/widgets/custom_button.dart', type: 'file', size: 890, lastModified: DateTime.now().subtract(const Duration(days: 2))),
        RepoFileItem(name: 'card_widget.dart', path: 'src/widgets/card_widget.dart', type: 'file', size: 1100, lastModified: DateTime.now().subtract(const Duration(days: 1))),
      ];
    }
    return [];
  }

  // ── Data Loading ───────────────────────────────────────────────────────────

  Future<void> _loadRepoInfo() async {
    try {
      await _svc.initialize();
      if (_svc.isAuthenticated) {
        final details = await _svc.getRepoDetails(widget.owner, widget.repoName);
        final branches = await _svc.getBranches(widget.owner, widget.repoName);
        setState(() {
          _repoDetails = details;
          _currentBranch = details['default_branch'] as String? ?? _currentBranch;
          _branches = branches.map((b) => b['name'] as String? ?? '').where((n) => n.isNotEmpty).toList();
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _loadDirectory(String path) async {
    setState(() => _filesLoading = true);
    try {
      if (_svc.isAuthenticated) {
        final contents = await _svc.getContents(
          widget.owner,
          widget.repoName,
          path: path.isEmpty ? null : path,
          ref: _currentBranch,
        );
        setState(() {
          _currentFiles = contents
              .map((c) => RepoFileItem.fromGitHubApi(c as Map<String, dynamic>))
              .toList();
          _filesLoading = false;
        });
      } else {
        // Demo mode
        setState(() {
          _currentFiles = _buildDemoSubFiles(path);
          _filesLoading = false;
        });
      }
    } catch (e) {
      setState(() => _filesLoading = false);
      _toast('Failed to load directory: \$e');
    }
  }

  Future<void> _loadReadme() async {
    try {
      if (_svc.isAuthenticated) {
        final content = await _svc.getFileContent(
          widget.owner,
          widget.repoName,
          'README.md',
          ref: _currentBranch,
        );
        setState(() => _readmeContent = content);
      } else {
        setState(() => _readmeContent = '''# ${widget.repoName}

${widget.description ?? 'A GitHub repository.'}

## Getting Started

This project is a starting point for a Flutter application.

```bash
flutter pub get
flutter run
```

## Features

- Clean architecture
- Dark mode UI
- GitHub integration
- Code editor with syntax highlighting

## Contributing

1. Fork the repository
2. Create a feature branch
3. Submit a pull request
''');
      }
    } catch (_) {
      // README may not exist
    }
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  void _onFileTap(RepoFileItem file) {
    if (file.isDirectory) {
      setState(() {
        _pathStack.add(file.path);
        _selectedFile = null;
      });
      _loadDirectory(file.path);
    } else {
      setState(() => _selectedFile = file);
      _loadFileContent(file);
    }
  }

  Future<void> _loadFileContent(RepoFileItem file) async {
    if (_svc.isAuthenticated && file.isFile) {
      try {
        final content = await _svc.getFileContent(
          widget.owner,
          widget.repoName,
          file.path,
          ref: _currentBranch,
        );
        setState(() {
          _selectedFile = RepoFileItem(
            name: file.name,
            path: file.path,
            type: file.type,
            size: file.size,
            sha: file.sha,
            content: content,
            lastModified: file.lastModified,
          );
        });
      } catch (e) {
        _toast('Failed to load file: \$e');
      }
    }
  }

  void _onBreadcrumbTap(int index) {
    if (index < 0) {
      // Root
      setState(() {
        _pathStack.clear();
        _selectedFile = null;
        _currentFiles = _demoRootFiles;
      });
    } else {
      final newPath = _pathStack[index];
      setState(() {
        _pathStack.removeRange(index + 1, _pathStack.length);
        _selectedFile = null;
      });
      _loadDirectory(newPath);
    }
  }

  // ── Context Menu ───────────────────────────────────────────────────────────

  void _showFileContextMenu(RepoFileItem file, Offset position) {
    final RenderBox overlay = Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(position, position.translate(0, 0)),
        Offset.zero & overlay.size,
      ),
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        PopupMenuItem(
          value: 'view',
          onTap: () => _onFileTap(file),
          child: const Row(children: [
            Icon(Icons.visibility, size: 18, color: AppTheme.primary),
            SizedBox(width: 10),
            Text('View', style: TextStyle(color: AppTheme.textPrimary)),
          ]),
        ),
        if (file.isFile) ...[
          PopupMenuItem(
            value: 'edit',
            onTap: () => setState(() {
              _selectedFile = file;
              _isEditing = true;
            }),
            child: const Row(children: [
              Icon(Icons.edit, size: 18, color: AppTheme.accent),
              SizedBox(width: 10),
              Text('Edit', style: TextStyle(color: AppTheme.textPrimary)),
            ]),
          ),
        ],
        PopupMenuItem(
          value: 'rename',
          onTap: () => _showRenameDialog(file),
          child: const Row(children: [
            Icon(Icons.drive_file_rename_outline, size: 18, color: AppTheme.info),
            SizedBox(width: 10),
            Text('Rename', style: TextStyle(color: AppTheme.textPrimary)),
          ]),
        ),
        PopupMenuItem(
          value: 'delete',
          onTap: () => _showDeleteConfirm(file),
          child: const Row(children: [
            Icon(Icons.delete_outline, size: 18, color: AppTheme.error),
            SizedBox(width: 10),
            Text('Delete', style: TextStyle(color: AppTheme.error)),
          ]),
        ),
        PopupMenuItem(
          value: 'copy',
          onTap: () {
            Clipboard.setData(ClipboardData(text: file.path));
            _toast('Path copied: ${file.path}');
          },
          child: const Row(children: [
            Icon(Icons.copy, size: 18, color: AppTheme.textSecondary),
            SizedBox(width: 10),
            Text('Copy Path', style: TextStyle(color: AppTheme.textPrimary)),
          ]),
        ),
      ],
    );
  }

  void _showRenameDialog(RepoFileItem file) {
    final ctrl = TextEditingController(text: file.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Rename', style: TextStyle(color: AppTheme.textPrimary)),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(
            labelText: 'New name',
            labelStyle: TextStyle(color: AppTheme.textSecondary),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.border)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.primary)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final newName = ctrl.text.trim();
              if (newName.isEmpty || newName == file.name) return;
              try {
                await _svc.renameFile(
                  widget.owner, widget.repoName,
                  file.path, newName,
                  'Rename ${file.name} to \$newName',
                  branch: _currentBranch,
                );
                _toast('Renamed to \$newName');
                _refreshCurrentDir();
              } catch (e) {
                _toast('Rename failed: \$e', isError: true);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirm(RepoFileItem file) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete File?', style: TextStyle(color: AppTheme.error)),
        content: Text('Are you sure you want to delete "${file.name}"? This action cannot be undone.',
            style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _svc.deleteFile(
                  widget.owner, widget.repoName,
                  file.path,
                  'Delete ${file.name}',
                  branch: _currentBranch,
                );
                _toast('Deleted ${file.name}');
                _refreshCurrentDir();
              } catch (e) {
                _toast('Delete failed: \$e', isError: true);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _refreshCurrentDir() {
    if (_pathStack.isEmpty) {
      _loadRepoInfo();
    } else {
      _loadDirectory(_pathStack.last);
    }
  }

  // ── Create Actions ─────────────────────────────────────────────────────────

  void _showNewFileDialog() {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('New File', style: TextStyle(color: AppTheme.textPrimary)),
        content: TextField(
          controller: nameCtrl,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(
            labelText: 'File name',
            labelStyle: TextStyle(color: AppTheme.textSecondary),
            hintText: 'example.dart',
            hintStyle: TextStyle(color: AppTheme.textTertiary),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.border)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.primary)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              final path = _pathStack.isEmpty ? name : '${_pathStack.last}/\$name';
              try {
                await _svc.createOrUpdateFile(
                  widget.owner, widget.repoName,
                  path, '',
                  'Create \$name',
                  branch: _currentBranch,
                );
                _toast('Created \$name');
                _refreshCurrentDir();
              } catch (e) {
                _toast('Failed: \$e', isError: true);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showNewFolderDialog() {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('New Folder', style: TextStyle(color: AppTheme.textPrimary)),
        content: TextField(
          controller: nameCtrl,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(
            labelText: 'Folder name',
            labelStyle: TextStyle(color: AppTheme.textSecondary),
            hintText: 'new_folder',
            hintStyle: TextStyle(color: AppTheme.textTertiary),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.border)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.primary)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              final path = _pathStack.isEmpty ? '\$name/.gitkeep' : '${_pathStack.last}/\$name/.gitkeep';
              try {
                await _svc.createOrUpdateFile(
                  widget.owner, widget.repoName,
                  path, '',
                  'Create directory \$name',
                  branch: _currentBranch,
                );
                _toast('Created folder \$name');
                _refreshCurrentDir();
              } catch (e) {
                _toast('Failed: \$e', isError: true);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  // ── Toasts ─────────────────────────────────────────────────────────────────

  void _toast(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: AppTheme.textPrimary)),
      backgroundColor: (isError ? AppTheme.error : AppTheme.success).withOpacity(0.9),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 3),
    ));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _svc.dispose();
    super.dispose();
  }


  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: const Center(
          child: CircularProgressIndicator(color: AppTheme.primary),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            // Branch selector + actions
            _buildBranchBar(),
            // Tabs
            Container(
              color: AppTheme.backgroundElevated,
              child: TabBar(
                controller: _tabController,
                indicatorColor: AppTheme.primary,
                labelColor: AppTheme.primary,
                unselectedLabelColor: AppTheme.textTertiary,
                labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                tabs: const [
                  Tab(icon: Icon(Icons.folder_outlined, size: 18), text: 'Files'),
                  Tab(icon: Icon(Icons.info_outline, size: 18), text: 'About'),
                ],
              ),
            ),
            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildFilesTab(),
                  _buildAboutTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Top Bar with Breadcrumb ────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: AppTheme.backgroundElevated,
        border: Border(bottom: BorderSide(color: AppTheme.divider)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, size: 20, color: AppTheme.textSecondary),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // Repo name (root)
                  InkWell(
                    onTap: () => _onBreadcrumbTap(-1),
                    child: Text(
                      widget.repoName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _pathStack.isEmpty ? AppTheme.textPrimary : AppTheme.accent,
                        fontFamily: AppTheme.fontCode,
                      ),
                    ),
                  ),
                  // Path segments
                  ..._pathStack.asMap().entries.expand((entry) {
                    final i = entry.key;
                    final segment = entry.value.split('/').last;
                    return [
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(Icons.chevron_right, size: 16, color: AppTheme.textTertiary),
                      ),
                      InkWell(
                        onTap: () => _onBreadcrumbTap(i),
                        child: Text(
                          segment,
                          style: TextStyle(
                            fontSize: 13,
                            color: i == _pathStack.length - 1
                                ? AppTheme.textPrimary
                                : AppTheme.accent,
                            fontWeight: i == _pathStack.length - 1
                                ? FontWeight.w500
                                : FontWeight.normal,
                            fontFamily: AppTheme.fontCode,
                          ),
                        ),
                      ),
                    ];
                  }),
                ],
              ),
            ),
          ),
          // File actions
          if (_selectedFile != null && !_selectedFile!.isDirectory) ...[
            if (!_isEditing)
              IconButton(
                onPressed: () => setState(() => _isEditing = true),
                icon: const Icon(Icons.edit, size: 20, color: AppTheme.accent),
                tooltip: 'Edit',
              )
            else
              IconButton(
                onPressed: () => _showCommitDialog(),
                icon: const Icon(Icons.check, size: 20, color: AppTheme.success),
                tooltip: 'Commit',
              ),
          ],
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  // ── Branch Selector Bar ────────────────────────────────────────────────────

  Widget _buildBranchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.backgroundElevated,
        border: Border(bottom: BorderSide(color: AppTheme.divider)),
      ),
      child: Row(
        children: [
          // Branch selector
          InkWell(
            onTap: _showBranchSelector,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.surface.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.account_tree, size: 14, color: AppTheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    _currentBranch,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: AppTheme.fontCode,
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.keyboard_arrow_down, size: 16, color: AppTheme.textTertiary),
                ],
              ),
            ),
          ),
          const Spacer(),
          // Quick action buttons
          _buildActionButton(Icons.upload_file, 'Upload', _showUploadDialog),
          const SizedBox(width: 6),
          _buildActionButton(Icons.note_add, 'New', _showNewFileDialog),
          const SizedBox(width: 6),
          _buildActionButton(Icons.create_new_folder, 'Folder', _showNewFolderDialog),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppTheme.surface.withOpacity(0.5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.border),
          ),
          child: Icon(icon, size: 16, color: AppTheme.textSecondary),
        ),
      ),
    );
  }

  void _showBranchSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Switch Branch',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 12),
            // Search/filter branches
            TextField(
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppTheme.surfaceInput,
                hintText: 'Filter branches...',
                hintStyle: const TextStyle(color: AppTheme.textTertiary),
                prefixIcon: const Icon(Icons.search, size: 18, color: AppTheme.textTertiary),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.border)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onChanged: (v) {
                // Filter branches logic handled by setState in real implementation
              },
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 300,
              child: ListView.builder(
                itemCount: _branches.length,
                itemBuilder: (_, i) {
                  final branch = _branches[i];
                  final isActive = branch == _currentBranch;
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      isActive ? Icons.check_circle : Icons.account_tree,
                      size: 18,
                      color: isActive ? AppTheme.primary : AppTheme.textTertiary,
                    ),
                    title: Text(branch,
                      style: TextStyle(
                        color: isActive ? AppTheme.primary : AppTheme.textPrimary,
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                        fontFamily: AppTheme.fontCode,
                        fontSize: 13,
                      ),
                    ),
                    trailing: isActive
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('ACTIVE', style: TextStyle(fontSize: 9, color: AppTheme.primary, fontWeight: FontWeight.w700)),
                        )
                      : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      if (!isActive) {
                        setState(() => _currentBranch = branch);
                        _loadReadme();
                        if (_pathStack.isNotEmpty) {
                          _loadDirectory(_pathStack.last);
                        }
                        _toast('Switched to branch \$branch');
                      }
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showUploadDialog() {
    _toast('File upload coming soon');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // FILES TAB
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildFilesTab() {
    if (_selectedFile != null && _selectedFile!.isFile && !_isEditing) {
      return _buildFileViewer();
    }
    if (_isEditing && _selectedFile != null) {
      return _buildFileEditor();
    }
    return Column(
      children: [
        // File count
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          alignment: Alignment.centerLeft,
          child: Text(
            '${_currentFiles.length} items',
            style: const TextStyle(fontSize: 12, color: AppTheme.textTertiary),
          ),
        ),
        // File list
        Expanded(
          child: _filesLoading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
            : RefreshIndicator(
                onRefresh: () async => _refreshCurrentDir(),
                color: AppTheme.primary,
                backgroundColor: AppTheme.surface,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  itemCount: _currentFiles.length,
                  itemBuilder: (_, i) => _buildFileItem(_currentFiles[i]),
                ),
              ),
        ),
        // README toggle
        if (_readmeContent != null && _pathStack.isEmpty && _selectedFile == null)
          _buildReadmeToggle(),
      ],
    );
  }

  Widget _buildFileItem(RepoFileItem file) {
    return InkWell(
      onTap: () => _onFileTap(file),
      onLongPress: () {
        final RenderBox box = context.findRenderObject() as RenderBox;
        _showFileContextMenu(file, box.localToGlobal(Offset.zero));
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(0.4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.border.withOpacity(0.5)),
        ),
        child: Row(
          children: [
            // File/directory icon
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: file.iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(file.icon, size: 20, color: file.iconColor),
            ),
            const SizedBox(width: 12),
            // File info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textPrimary,
                      fontFamily: AppTheme.fontCode,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (file.formattedSize.isNotEmpty)
                        Text(
                          file.formattedSize,
                          style: const TextStyle(fontSize: 11, color: AppTheme.textTertiary),
                        ),
                      if (file.formattedSize.isNotEmpty)
                        const SizedBox(width: 10),
                      if (file.lastModified != null)
                        Text(
                          _ago(file.lastModified!),
                          style: const TextStyle(fontSize: 11, color: AppTheme.textTertiary),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            // Trailing icon
            if (file.isDirectory)
              const Icon(Icons.chevron_right, size: 18, color: AppTheme.textTertiary)
            else
              IconButton(
                icon: const Icon(Icons.more_vert, size: 18, color: AppTheme.textTertiary),
                onPressed: () {
                  final RenderBox box = context.findRenderObject() as RenderBox;
                  _showFileContextMenu(file, box.localToGlobal(Offset.zero));
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
          ],
        ),
      ),
    );
  }

  // ── File Viewer ────────────────────────────────────────────────────────────

  Widget _buildFileViewer() {
    return Column(
      children: [
        // Read-only indicator
        Container(
          height: 32,
          color: AppTheme.backgroundElevated,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.visibility, size: 14, color: AppTheme.textTertiary),
              const SizedBox(width: 6),
              Text(
                '${_selectedFile!.name} \u00B7 ${_selectedFile!.formattedSize}',
                style: const TextStyle(fontSize: 12, color: AppTheme.textTertiary),
              ),
            ],
          ),
        ),
        // File content
        Expanded(
          child: Container(
            color: AppTheme.editorBackground,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                _selectedFile!.content ?? 'No content available.',
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: AppTheme.fontCode,
                  color: AppTheme.textPrimary.withOpacity(0.9),
                  height: 1.6,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFileEditor() {
    return Column(
      children: [
        Container(
          height: 32,
          color: AppTheme.backgroundElevated,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.edit, size: 14, color: AppTheme.accent),
              const SizedBox(width: 6),
              Text(
                'Editing: ${_selectedFile!.name}',
                style: const TextStyle(fontSize: 12, color: AppTheme.accent),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: AppTheme.editorBackground,
            child: TextField(
              controller: TextEditingController(text: _selectedFile!.content ?? ''),
              style: TextStyle(
                fontSize: 13,
                fontFamily: AppTheme.fontCode,
                color: AppTheme.textPrimary.withOpacity(0.9),
                height: 1.6,
              ),
              maxLines: null,
              expands: true,
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(16),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showCommitDialog() {
    final messageController = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          top: 20,
          left: 20,
          right: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)),
            )),
            const SizedBox(height: 20),
            const Text('Commit Changes',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 8),
            Text('File: ${_selectedFile?.name}',
              style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: messageController,
              autofocus: true,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppTheme.surfaceInput,
                labelText: 'Commit message',
                labelStyle: const TextStyle(color: AppTheme.textSecondary),
                hintText: 'Update ${_selectedFile?.name}',
                hintStyle: const TextStyle(color: AppTheme.textTertiary),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  if (messageController.text.isNotEmpty && _selectedFile != null) {
                    setState(() => _isEditing = false);
                    Navigator.pop(context);
                    try {
                      await _svc.createOrUpdateFile(
                        widget.owner, widget.repoName,
                        _selectedFile!.path,
                        _selectedFile!.content ?? '',
                        messageController.text,
                        branch: _currentBranch,
                      );
                      _toast('Committed changes');
                    } catch (e) {
                      _toast('Commit failed: \$e', isError: true);
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Commit', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── README ─────────────────────────────────────────────────────────────────

  Widget _buildReadmeToggle() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.backgroundElevated,
        border: Border(top: BorderSide(color: AppTheme.divider)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _readmeVisible = !_readmeVisible),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.article, size: 16, color: AppTheme.accent),
                  const SizedBox(width: 8),
                  const Text('README.md',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _readmeVisible ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down, size: 20, color: AppTheme.textTertiary),
                  ),
                ],
              ),
            ),
          ),
          if (_readmeVisible && _readmeContent != null)
            Container(
              height: 300,
              color: AppTheme.editorBackground,
              child: Markdown(
                data: _readmeContent!,
                selectable: true,
                styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                  p: const TextStyle(fontSize: 14, color: AppTheme.textSecondary, height: 1.6),
                  h1: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  h2: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  h3: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                  code: TextStyle(
                    fontSize: 12,
                    fontFamily: AppTheme.fontCode,
                    color: AppTheme.textPrimary,
                    backgroundColor: AppTheme.surfaceHover,
                  ),
                  codeblockDecoration: BoxDecoration(
                    color: AppTheme.surfaceHover,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.border),
                  ),
                  blockquote: const TextStyle(fontSize: 14, color: AppTheme.textSecondary, fontStyle: FontStyle.italic),
                  blockquoteDecoration: BoxDecoration(
                    border: Border(left: BorderSide(color: AppTheme.primary, width: 3)),
                    color: AppTheme.primary.withOpacity(0.05),
                  ),
                  listBullet: const TextStyle(color: AppTheme.textSecondary),
                  a: const TextStyle(color: AppTheme.accent, decoration: TextDecoration.underline),
                ),
                onTapLink: (text, href, title) {
                  if (href != null) launchUrl(Uri.parse(href));
                },
              ),
            ),
        ],
      ),
    );
  }


  // ═══════════════════════════════════════════════════════════════════════════
  // ABOUT TAB (Repo Info)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildAboutTab() {
    final stars = _repoDetails['stargazers_count'] as int? ?? 0;
    final forks = _repoDetails['forks_count'] as int? ?? 0;
    final watchers = _repoDetails['watchers_count'] as int? ?? 0;
    final openIssues = _repoDetails['open_issues_count'] as int? ?? 0;
    final topics = (_repoDetails['topics'] as List<dynamic>?)?.cast<String>() ?? [];
    final license = (_repoDetails['license'] as Map<String, dynamic>?)?.cast<String, dynamic>()?['name'] as String?;
    final language = _repoDetails['language'] as String? ?? widget.language;
    final description = _repoDetails['description'] as String? ?? widget.description ?? '';
    final isPrivate = _repoDetails['private'] as bool? ?? false;
    final createdAt = _repoDetails['created_at'] != null
        ? DateTime.tryParse(_repoDetails['created_at'] as String)
        : null;

    return RefreshIndicator(
      onRefresh: _loadRepoInfo,
      color: AppTheme.primary,
      backgroundColor: AppTheme.surface,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Repo header card
          GlassCardWidget(
            padding: const EdgeInsets.all(20),
            borderRadius: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${widget.owner}/${widget.repoName}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                          fontFamily: AppTheme.fontCode,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isPrivate ? AppTheme.warning.withOpacity(0.15) : AppTheme.success.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isPrivate ? AppTheme.warning.withOpacity(0.3) : AppTheme.success.withOpacity(0.3),
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        isPrivate ? 'PRIVATE' : 'PUBLIC',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: isPrivate ? AppTheme.warning : AppTheme.success,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    description,
                    style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary, height: 1.5),
                  ),
                ],
                if (createdAt != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Created ${_ago(createdAt)}',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textTertiary),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Stats grid
          Row(
            children: [
              Expanded(child: _buildStatCard(Icons.star, 'Stars', '$stars', AppTheme.warning)),
              const SizedBox(width: 8),
              Expanded(child: _buildStatCard(Icons.call_split, 'Forks', '$forks', AppTheme.accent)),
              const SizedBox(width: 8),
              Expanded(child: _buildStatCard(Icons.visibility, 'Watch', '$watchers', AppTheme.info)),
              const SizedBox(width: 8),
              Expanded(child: _buildStatCard(Icons.error_outline, 'Issues', '$openIssues', AppTheme.error)),
            ],
          ),
          const SizedBox(height: 16),

          // Language bar
          if (language != null) ...[
            const Text('Languages',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 10),
            _buildLanguageBar(language),
            const SizedBox(height: 16),
          ],

          // Topics
          if (topics.isNotEmpty) ...[
            const Text('Topics',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: topics.map((t) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
                ),
                child: Text(
                  t,
                  style: const TextStyle(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.w500),
                ),
              )).toList(),
            ),
            const SizedBox(height: 16),
          ],

          // License
          if (license != null)
            _buildInfoRow(Icons.balance, 'License', license),
          _buildInfoRow(Icons.code, 'Default Branch', _currentBranch),
          _buildInfoRow(Icons.language, 'Language', language ?? 'Unknown'),

          const SizedBox(height: 20),

          // "Open in MobileCode" button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                _toast('Cloning to local workspace...');
                // Integration with local workspace
              },
              icon: const Icon(Icons.computer, size: 18),
              label: const Text('Open in MobileCode', style: TextStyle(fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // GitHub link
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                final url = 'https://github.com/${widget.owner}/${widget.repoName}';
                launchUrl(Uri.parse(url));
              },
              icon: const Icon(Icons.open_in_browser, size: 18),
              label: const Text('View on GitHub', style: TextStyle(fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textPrimary,
                side: const BorderSide(color: AppTheme.border),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(IconData icon, String label, String value, Color color) {
    return GlassCardWidget(
      padding: const EdgeInsets.all(12),
      borderRadius: 12,
      child: Column(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppTheme.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageBar(String primaryLanguage) {
    final colors = _GitHubRepoScreenState._languageColors;
    final primaryColor = colors[primaryLanguage] ?? AppTheme.primary;
    // Simulated language distribution
    final langSegments = [
      (primaryLanguage, 0.65, primaryColor),
      ('Other', 0.35, AppTheme.textTertiary),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Bar
        Container(
          height: 8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: AppTheme.surfaceHover,
          ),
          child: Row(
            children: langSegments.map((seg) {
              final (_, pct, color) = seg;
              return Expanded(
                flex: (pct * 100).round(),
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        // Legend
        Wrap(
          spacing: 12,
          children: langSegments.map((seg) {
            final (name, pct, color) = seg;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 4),
                Text(
                  '$name ${(pct * 100).toInt()}%',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.divider.withOpacity(0.5))),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.textTertiary),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppTheme.textPrimary,
              fontFamily: AppTheme.fontCode,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UTILITIES
  // ═══════════════════════════════════════════════════════════════════════════

  String _ago(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inDays > 365) return '${diff.inDays ~/ 365}y ago';
    if (diff.inDays > 30) return '${diff.inDays ~/ 30}mo ago';
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'just now';
  }
}
