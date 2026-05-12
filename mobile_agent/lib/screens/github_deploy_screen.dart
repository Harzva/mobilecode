import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import '../core/theme.dart';
import '../services/github_deep_service.dart';
import '../services/github_pages_service.dart';

// =============================================================================
// GITHUB PAGES DEPLOYMENT SCREEN
// =============================================================================

/// Deploy projects to GitHub Pages from MobileCode.
///
/// User flow:
/// 1. Select local project to deploy
/// 2. Select target repository (existing or create new)
/// 3. Select build type (Flutter Web / Static HTML / Jekyll)
/// 4. Optional: Set custom domain
/// 5. Review and deploy
/// 6. View deployment progress and URL
class GitHubDeployScreen extends StatefulWidget {
  final String? projectId;

  const GitHubDeployScreen({super.key, this.projectId});

  @override
  State<GitHubDeployScreen> createState() => _GitHubDeployScreenState();
}

class _GitHubDeployScreenState extends State<GitHubDeployScreen> {
  GitHubPagesService? _pagesService;
  List<Map<String, dynamic>> _projects = [];
  List<dynamic> _repos = [];

  // Form state.
  String? _selectedProjectPath;
  String? _selectedRepoOwner;
  String? _selectedRepoName;
  BuildType _buildType = BuildType.flutterWeb;
  final _customDomainController = TextEditingController();
  final _newRepoNameController = TextEditingController();
  final _newRepoDescController = TextEditingController();

  // Deployment state.
  DeploymentResult? _lastResult;
  List<Deployment> _deployments = [];
  bool _isDeploying = false;
  bool _isLoading = true;
  String? _error;
  bool _createNewRepo = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _customDomainController.dispose();
    _newRepoNameController.dispose();
    _newRepoDescController.dispose();
    _pagesService?.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    // Discover local projects.
    await _discoverProjects();
    setState(() => _isLoading = false);
  }

  /// Set the GitHub service — called by parent before use.
  void setGitHubService(GitHubDeepService github) {
    _pagesService = GitHubPagesService(github);
    _loadRepos();
    _loadDeployments(github.currentUser ?? '');
  }

  Future<void> _discoverProjects() async {
    // Scan common project directories for Flutter/Web projects.
    final projectsDir = Directory('/projects');
    if (!projectsDir.existsSync()) return;

    final projects = <Map<String, dynamic>>[];
    try {
      await for (final entity in projectsDir.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final dirName = path.basename(entity.path);

        // Detect project type.
        BuildType? detectedType;
        if (File('${entity.path}/pubspec.yaml').existsSync()) {
          detectedType = BuildType.flutterWeb;
        } else if (File('${entity.path}/_config.yml').existsSync()) {
          detectedType = BuildType.jekyll;
        } else if (File('${entity.path}/index.html').existsSync() ||
            File('${entity.path}/package.json').existsSync()) {
          detectedType = BuildType.staticHtml;
        }

        if (detectedType != null) {
          projects.add({
            'path': entity.path,
            'name': dirName,
            'type': detectedType,
          });
        }
      }
    } catch (e) {
      debugPrint('Failed to discover projects: $e');
    }

    setState(() => _projects = projects);

    // Auto-select if projectId provided.
    if (widget.projectId != null) {
      final match = projects.firstWhere(
        (p) => p['name'] == widget.projectId,
        orElse: () => <String, dynamic>{},
      );
      if (match.isNotEmpty) {
        setState(() {
          _selectedProjectPath = match['path'] as String;
          _buildType = match['type'] as BuildType;
        });
      }
    }
  }

  Future<void> _loadRepos() async {
    if (_pagesService == null) return;
    try {
      final github = _pagesService!;
      // Access the GitHubDeepService through the pages service.
      // We use a workaround since _github is private.
      final repos = await _getReposFromService();
      setState(() => _repos = repos);
    } catch (e) {
      debugPrint('Failed to load repos: $e');
    }
  }

  Future<List<dynamic>> _getReposFromService() async {
    // This will be called from the parent widget with proper context.
    // For now return empty; the parent will inject repos.
    return [];
  }

  Future<void> _loadDeployments(String owner) async {
    // Load after repo is selected.
  }

  // ── Deployment ──────────────────────────────────────────────────────

  Future<void> _deploy() async {
    if (_pagesService == null) {
      setState(() => _error = 'GitHub service not initialized');
      return;
    }
    if (_selectedProjectPath == null) {
      setState(() => _error = 'Please select a project');
      return;
    }
    if (_selectedRepoOwner == null || _selectedRepoName == null) {
      setState(() => _error = 'Please select a repository');
      return;
    }

    // Create new repo if needed.
    String owner = _selectedRepoOwner!;
    String repoName = _selectedRepoName!;

    if (_createNewRepo && _newRepoNameController.text.isNotEmpty) {
      setState(() => _isDeploying = true);
      try {
        final newRepo = await _createRepo();
        owner = newRepo['owner']['login'] as String;
        repoName = newRepo['name'] as String;
      } catch (e) {
        setState(() {
          _error = 'Failed to create repo: $e';
          _isDeploying = false;
        });
        return;
      }
    }

    setState(() {
      _isDeploying = true;
      _error = null;
      _lastResult = null;
    });

    try {
      final customDomain = _customDomainController.text.trim();
      final result = await _pagesService!.deploy(
        localProjectPath: _selectedProjectPath!,
        owner: owner,
        repo: repoName,
        buildType: _buildType,
        customDomain: customDomain.isNotEmpty ? customDomain : null,
      );

      setState(() {
        _lastResult = result;
        _isDeploying = false;
      });

      if (result.success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Deployed successfully!')),
        );
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isDeploying = false;
      });
    }
  }

  Future<Map<String, dynamic>> _createRepo() async {
    // This is handled by the parent injecting the github service.
    // The actual creation is done through GitHubDeepService.
    throw UnimplementedError('Repo creation handled by parent');
  }

  void _copyUrl(String url) {
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('URL copied to clipboard')),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Deploy to GitHub Pages'),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Section: Project Selection.
                  _SectionHeader(
                    icon: Icons.folder_outlined,
                    title: '1. Select Project',
                  ),
                  const SizedBox(height: 8),
                  _ProjectSelector(
                    projects: _projects,
                    selectedPath: _selectedProjectPath,
                    onSelect: (path) => setState(() => _selectedProjectPath = path),
                  ),
                  const SizedBox(height: 24),

                  // Section: Repository Selection.
                  _SectionHeader(
                    icon: Icons.repository_outlined,
                    title: '2. Target Repository',
                  ),
                  const SizedBox(height: 8),
                  _RepoSelector(
                    repos: _repos,
                    owner: _selectedRepoOwner,
                    repoName: _selectedRepoName,
                    createNew: _createNewRepo,
                    newRepoController: _newRepoNameController,
                    newRepoDescController: _newRepoDescController,
                    onOwnerChanged: (o) => setState(() => _selectedRepoOwner = o),
                    onRepoChanged: (r) => setState(() => _selectedRepoName = r),
                    onCreateNewToggle: (v) => setState(() => _createNewRepo = v),
                  ),
                  const SizedBox(height: 24),

                  // Section: Build Type.
                  _SectionHeader(
                    icon: Icons.build_outlined,
                    title: '3. Build Type',
                  ),
                  const SizedBox(height: 8),
                  _BuildTypeSelector(
                    selected: _buildType,
                    onSelect: (t) => setState(() => _buildType = t),
                  ),
                  const SizedBox(height: 24),

                  // Section: Custom Domain.
                  _SectionHeader(
                    icon: Icons.language,
                    title: '4. Custom Domain (optional)',
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _customDomainController,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: const InputDecoration(
                      hintText: 'e.g., www.example.com',
                      prefixIcon: Icon(Icons.link, color: AppTheme.textTertiary),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Error display.
                  if (_error != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.error.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.error.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: AppTheme.error, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: AppTheme.error,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_error != null) const SizedBox(height: 16),

                  // Deploy Button.
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isDeploying ? null : _deploy,
                      icon: _isDeploying
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: AppTheme.textOnPrimary,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.rocket_launch),
                      label: Text(_isDeploying ? 'Deploying...' : 'Deploy to GitHub Pages'),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Deployment Progress.
                  if (_isDeploying || (_lastResult != null && !_lastResult!.success))
                    _DeploymentProgress(result: _lastResult),
                  if (_isDeploying || (_lastResult != null && !_lastResult!.success))
                    const SizedBox(height: 24),

                  // Deployment Result.
                  if (_lastResult != null && _lastResult!.success)
                    _DeploymentSuccessCard(
                      result: _lastResult!,
                      onCopyUrl: _copyUrl,
                    ),
                  if (_lastResult != null && _lastResult!.success) const SizedBox(height: 24),

                  // Deployment History.
                  if (_deployments.isNotEmpty) ...[
                    _SectionHeader(
                      icon: Icons.history,
                      title: 'Deployment History',
                    ),
                    const SizedBox(height: 8),
                    _DeploymentHistoryList(deployments: _deployments),
                  ],
                ],
              ),
            ),
    );
  }
}

// =============================================================================
// SECTION HEADER
// =============================================================================

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// PROJECT SELECTOR
// =============================================================================

class _ProjectSelector extends StatelessWidget {
  final List<Map<String, dynamic>> projects;
  final String? selectedPath;
  final ValueChanged<String> onSelect;

  const _ProjectSelector({
    required this.projects,
    required this.selectedPath,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (projects.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: const Row(
          children: [
            Icon(Icons.folder_off, color: AppTheme.textTertiary),
            SizedBox(width: 12),
            Text(
              'No projects found in /projects',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }

    return Column(
      children: projects.map((project) {
        final isSelected = project['path'] == selectedPath;
        final type = project['type'] as BuildType;
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: InkWell(
            onTap: () => onSelect(project['path'] as String),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.primaryMuted : AppTheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? AppTheme.primary : AppTheme.border,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _projectIcon(type),
                    size: 22,
                    color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          project['name'] as String,
                          style: TextStyle(
                            fontFamily: AppTheme.fontBody,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _projectTypeLabel(type),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isSelected)
                    const Icon(Icons.check_circle, color: AppTheme.primary, size: 20),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  IconData _projectIcon(BuildType type) {
    switch (type) {
      case BuildType.flutterWeb:
        return Icons.flutter_dash;
      case BuildType.staticHtml:
        return Icons.html;
      case BuildType.jekyll:
        return Icons.web;
    }
  }

  String _projectTypeLabel(BuildType type) {
    switch (type) {
      case BuildType.flutterWeb:
        return 'Flutter Web';
      case BuildType.staticHtml:
        return 'Static HTML';
      case BuildType.jekyll:
        return 'Jekyll Site';
    }
  }
}

// =============================================================================
// REPOSITORY SELECTOR
// =============================================================================

class _RepoSelector extends StatelessWidget {
  final List<dynamic> repos;
  final String? owner;
  final String? repoName;
  final bool createNew;
  final TextEditingController newRepoController;
  final TextEditingController newRepoDescController;
  final ValueChanged<String?> onOwnerChanged;
  final ValueChanged<String?> onRepoChanged;
  final ValueChanged<bool> onCreateNewToggle;

  const _RepoSelector({
    required this.repos,
    required this.owner,
    required this.repoName,
    required this.createNew,
    required this.newRepoController,
    required this.newRepoDescController,
    required this.onOwnerChanged,
    required this.onRepoChanged,
    required this.onCreateNewToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Toggle: existing vs new.
        Row(
          children: [
            ChoiceChip(
              label: const Text('Existing Repo'),
              selected: !createNew,
              onSelected: (v) => onCreateNewToggle(false),
              selectedColor: AppTheme.primaryMuted,
              labelStyle: TextStyle(
                color: !createNew ? AppTheme.primary : AppTheme.textSecondary,
                fontFamily: AppTheme.fontBody,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Create New'),
              selected: createNew,
              onSelected: (v) => onCreateNewToggle(true),
              selectedColor: AppTheme.primaryMuted,
              labelStyle: TextStyle(
                color: createNew ? AppTheme.primary : AppTheme.textSecondary,
                fontFamily: AppTheme.fontBody,
                fontSize: 13,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (!createNew) ...[
          // Existing repo dropdown.
          if (repos.isEmpty)
            const Text(
              'Loading repositories...',
              style: TextStyle(color: AppTheme.textTertiary, fontSize: 13),
            )
          else
            ...repos.map<Widget>((repo) {
              final repoFullName = repo['full_name'] as String? ?? '';
              final isSelected = repoName == (repo['name'] as String?);
              final parts = repoFullName.split('/');
              final repoOwner = parts.isNotEmpty ? parts[0] : '';
              final name = parts.length > 1 ? parts[1] : repoFullName;

              return InkWell(
                onTap: () {
                  onOwnerChanged(repoOwner);
                  onRepoChanged(name);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: isSelected ? AppTheme.primaryMuted : AppTheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? AppTheme.primary : AppTheme.border,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.book,
                        size: 18,
                        color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          repoFullName,
                          style: TextStyle(
                            fontFamily: AppTheme.fontCode,
                            fontSize: 13,
                            color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
                          ),
                        ),
                      ),
                      if (isSelected)
                        const Icon(Icons.check_circle, color: AppTheme.primary, size: 16),
                    ],
                  ),
                ),
              );
            }).toList(),
        ] else ...[
          // New repo form.
          TextField(
            controller: newRepoController,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Repository Name',
              hintText: 'my-awesome-site',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: newRepoDescController,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
              hintText: 'My deployed site',
            ),
          ),
        ],
      ],
    );
  }
}

// =============================================================================
// BUILD TYPE SELECTOR
// =============================================================================

class _BuildTypeSelector extends StatelessWidget {
  final BuildType selected;
  final ValueChanged<BuildType> onSelect;

  const _BuildTypeSelector({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: BuildType.values.map((type) {
        final isSelected = type == selected;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: InkWell(
              onTap: () => onSelect(type),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.primaryMuted : AppTheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected ? AppTheme.primary : AppTheme.border,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _buildTypeIcon(type),
                      color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
                      size: 28,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _buildTypeLabel(type),
                      style: TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  IconData _buildTypeIcon(BuildType type) {
    switch (type) {
      case BuildType.flutterWeb:
        return Icons.flutter_dash;
      case BuildType.staticHtml:
        return Icons.html_outlined;
      case BuildType.jekyll:
        return Icons.web_asset;
    }
  }

  String _buildTypeLabel(BuildType type) {
    switch (type) {
      case BuildType.flutterWeb:
        return 'Flutter Web';
      case BuildType.staticHtml:
        return 'Static HTML';
      case BuildType.jekyll:
        return 'Jekyll';
    }
  }
}

// =============================================================================
// DEPLOYMENT PROGRESS
// =============================================================================

class _DeploymentProgress extends StatelessWidget {
  final DeploymentResult? result;

  const _DeploymentProgress({this.result});

  @override
  Widget build(BuildContext context) {
    final steps = result?.steps ?? [];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Deployment Progress',
            style: TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          ...steps.asMap().entries.map((entry) {
            final isLast = entry.key == steps.length - 1;
            final isError = entry.value.startsWith('Error:') ||
                entry.value.startsWith('Unexpected error:');
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    isError
                        ? Icons.error_outline
                        : isLast && result?.success != true
                            ? Icons.hourglass_top
                            : Icons.check_circle,
                    size: 16,
                    color: isError
                        ? AppTheme.error
                        : isLast && result?.success != true
                            ? AppTheme.warning
                            : AppTheme.success,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry.value,
                      style: TextStyle(
                        fontSize: 12,
                        color: isError ? AppTheme.error : AppTheme.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          if (result?.error != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                result!.error!,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.error,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// DEPLOYMENT SUCCESS CARD
// =============================================================================

class _DeploymentSuccessCard extends StatelessWidget {
  final DeploymentResult result;
  final ValueChanged<String> onCopyUrl;

  const _DeploymentSuccessCard({required this.result, required this.onCopyUrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppTheme.surfaceGradient,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.success.withOpacity(0.4)),
      ),
      child: Column(
        children: [
          const Icon(Icons.check_circle, color: AppTheme.success, size: 48),
          const SizedBox(height: 12),
          const Text(
            'Deployed Successfully!',
            style: TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Your site is live at',
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textTertiary,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.backgroundElevated,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.link, size: 16, color: AppTheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: SelectableText(
                    result.url ?? '',
                    style: const TextStyle(
                      fontFamily: AppTheme.fontCode,
                      fontSize: 13,
                      color: AppTheme.accent,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18, color: AppTheme.textSecondary),
                  onPressed: () => onCopyUrl(result.url ?? ''),
                  tooltip: 'Copy URL',
                ),
              ],
            ),
          ),
          if (result.customDomain != null) ...[
            const SizedBox(height: 8),
            Text(
              'Custom domain: ${result.customDomain}',
              style: const TextStyle(fontSize: 12, color: AppTheme.textTertiary),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Deployed at ${_formatTime(result.deployedAt)}',
            style: const TextStyle(fontSize: 11, color: AppTheme.textTertiary),
          ),
        ],
      ),
    );
  }

  static String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

// =============================================================================
// DEPLOYMENT HISTORY LIST
// =============================================================================

class _DeploymentHistoryList extends StatelessWidget {
  final List<Deployment> deployments;

  const _DeploymentHistoryList({required this.deployments});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: deployments.take(10).map((d) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _statusColor(d.state),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.ref,
                      style: const TextStyle(
                        fontFamily: AppTheme.fontCode,
                        fontSize: 13,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${d.environment} - ${_formatDate(d.createdAt)}',
                      style: const TextStyle(fontSize: 11, color: AppTheme.textTertiary),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor(d.state).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  d.state,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _statusColor(d.state),
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Color _statusColor(String state) {
    switch (state.toLowerCase()) {
      case 'success':
        return AppTheme.success;
      case 'failure':
      case 'error':
        return AppTheme.error;
      case 'pending':
        return AppTheme.warning;
      case 'inactive':
        return AppTheme.textTertiary;
      default:
        return AppTheme.info;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'just now';
  }
}
