import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import 'downloads_shared_folders_screen.dart';
import '../models/github_repo.dart';
import '../models/skill_model.dart';
import '../services/github_deep_service.dart';
import '../services/github_repo_hub_service.dart';
import '../services/memory_service.dart';
import '../services/mobile_code_helper_provider.dart';
import '../services/repo_knowledge_digest_service.dart';
import '../services/role_library_service.dart';
import '../services/runtime_manager.dart';
import '../services/runtime_provider.dart';
import '../services/skill_manager_service.dart';
import '../services/termux_service.dart';

const _bg = Color(0xFFF7FAFF);
const _panel = Color(0xFFFFFFFF);
const _line = Color(0xFFDDE7F7);
const _text = Color(0xFF0B1020);
const _muted = Color(0xFF536079);
const _faint = Color(0xFF8B97AD);
const _blue = Color(0xFF2555FF);
const _mint = Color(0xFF0B9B7E);
const _amber = Color(0xFFB7791F);
const _rose = Color(0xFFE0526E);
const _violet = Color(0xFF7557E8);

class GitHubRepoChatRequest {
  const GitHubRepoChatRequest({
    required this.repoFullName,
    required this.repoUrl,
    required this.workspaceMode,
    required this.prompt,
    this.pagesUrl,
    this.actionsUrl,
    this.workspacePath,
  });

  final String repoFullName;
  final String repoUrl;
  final String workspaceMode;
  final String prompt;
  final String? pagesUrl;
  final String? actionsUrl;
  final String? workspacePath;
}

class GitHubRepoHubScreen extends StatefulWidget {
  const GitHubRepoHubScreen({super.key});

  @override
  State<GitHubRepoHubScreen> createState() => _GitHubRepoHubScreenState();
}

class _GitHubRepoHubScreenState extends State<GitHubRepoHubScreen> {
  late final GitHubDeepService _github;
  late final GitHubRepoHubService _hub;
  late final RuntimeManager _runtimeManager;
  late final SkillManagerService _skillManager;
  late final RepoKnowledgeDigestService _repoKnowledge;
  final MemoryService _memory = MemoryService();
  final RoleLibraryService _roles = RoleLibraryService.instance;
  final _ownerController = TextEditingController();
  final _searchController = TextEditingController();

  bool _loading = true;
  bool _authenticated = false;
  bool _hasLoaded = false;
  String? _error;
  String? _notice;
  String _filter = 'all';
  String _languageFilter = 'all';
  String _sort = 'pushed';
  String _source = 'repo';
  List<GitHubRepoHubItem> _items = const [];
  Set<String> _cloningKeys = const {};
  Set<String> _installingKeys = const {};
  bool _analyzingKnowledge = false;

  @override
  void initState() {
    super.initState();
    _github = GitHubDeepService();
    _hub = GitHubRepoHubService(_github);
    _runtimeManager = RuntimeManager.withExternalTermux(TermuxService());
    _skillManager = SkillManagerService.instance;
    _repoKnowledge = RepoKnowledgeDigestService();
    _searchController.addListener(() => setState(() {}));
    unawaited(_skillManager.initialize().then((_) {
      if (mounted) setState(() {});
    }));
    unawaited(_memory.init());
    unawaited(_roles.initialize());
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _ownerController.dispose();
    _searchController.dispose();
    _github.dispose();
    unawaited(_runtimeManager.dispose());
    super.dispose();
  }

  List<GitHubRepoHubItem> get _visibleItems {
    final query = _searchController.text.trim().toLowerCase();
    return _items.where((item) {
      final repo = item.repo;
      final matchesQuery = query.isEmpty ||
          repo.fullName.toLowerCase().contains(query) ||
          repo.description.toLowerCase().contains(query) ||
          (repo.language ?? '').toLowerCase().contains(query);
      if (!matchesQuery) return false;
      if (_languageFilter != 'all' && (repo.language ?? '').toLowerCase() != _languageFilter) {
        return false;
      }
      return switch (_filter) {
        'watched' => item.watched,
        'local' => item.localState.exists,
        'git' => item.localState.hasGit,
        'pages' => repo.hasPages,
        _ => true,
      };
    }).toList();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });
    try {
      await _hub.initialize();
      final authenticated = _hub.isAuthenticated;
      final owner = _ownerController.text.trim();
      if (_source == 'owner' && owner.isEmpty && !authenticated) {
        if (!mounted) return;
        setState(() {
          _authenticated = false;
          _loading = false;
          _items = const [];
          _hasLoaded = false;
          _notice = '输入 GitHub user/org 可以匿名浏览公开仓库；登录后空白输入会加载自己的仓库。';
        });
        return;
      }
      final items = _source == 'owner'
          ? await _hub.loadHubItems(
              owner: owner,
              sort: _sort,
            )
          : await _hub.searchHubItems(
              query: owner,
              source: _source,
              sort: _sort,
            );
      if (!mounted) return;
      final keepLanguageFilter = _languageFilter == 'all' ||
          items.any((item) => (item.repo.language ?? '').toLowerCase() == _languageFilter);
      setState(() {
        _authenticated = authenticated;
        _items = items;
        _hasLoaded = true;
        if (!keepLanguageFilter) _languageFilter = 'all';
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasLoaded = true;
        _authenticated = _hub.isAuthenticated;
        _error = _friendlyGitHubError(error);
      });
    }
  }

  Future<void> _openLogin() async {
    final tokenController = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _panel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (sheetContext) {
        var connecting = false;
        String? error;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> connect() async {
              final token = tokenController.text.trim();
              if (token.isEmpty || connecting) return;
              setSheetState(() {
                connecting = true;
                error = null;
              });
              final success = await _github.authenticate(token);
              if (!sheetContext.mounted) return;
              if (success) {
                Navigator.of(sheetContext).pop(true);
              } else {
                setSheetState(() {
                  connecting = false;
                  error = 'Token 无法访问 GitHub /user。请确认 token 有效，且没有多余空格。';
                });
              }
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.of(context).viewInsets.bottom + 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(color: _line, borderRadius: BorderRadius.circular(99)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Add GitHub access', style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 18)),
                  const SizedBox(height: 6),
                  const Text(
                    '公开搜索不需要登录；token 只用于加载私有仓库、发布 Pages、触发 Actions、提交文件等账号操作。',
                    style: TextStyle(color: _muted, height: 1.35),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: tokenController,
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => unawaited(connect()),
                    decoration: const InputDecoration(
                      labelText: 'GitHub access token',
                      hintText: 'ghp_... / github_pat_...',
                      prefixIcon: Icon(Icons.key_outlined),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(error!, style: const TextStyle(color: _rose, height: 1.35)),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: connecting ? null : () => Navigator.of(sheetContext).pop(false),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: connecting ? null : () => unawaited(connect()),
                          icon: connecting
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.login_outlined),
                          label: Text(connecting ? 'Connecting' : 'Save access'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    tokenController.dispose();
    if (!mounted) return;
    if (ok == true) {
      _toast('GitHub access saved.');
      setState(() {
        _source = 'owner';
        _ownerController.clear();
        _filter = 'all';
        _languageFilter = 'all';
      });
      await _refresh();
    }
  }

  Future<void> _setWatched(GitHubRepoHubItem item, bool watched) async {
    await _hub.setWatched(item.repo, watched);
    final next = <GitHubRepoHubItem>[];
    for (final current in _items) {
      next.add(current.key == item.key
          ? GitHubRepoHubItem(repo: current.repo, localState: current.localState, watched: watched)
          : current);
    }
    if (!mounted) return;
    setState(() => _items = next);
  }

  Future<void> _linkWorkspace(GitHubRepoHubItem item) async {
    try {
      final local = await _hub.ensureRemoteLinkedWorkspace(item.repo);
      final next = <GitHubRepoHubItem>[];
      for (final current in _items) {
        next.add(current.key == item.key
            ? GitHubRepoHubItem(repo: current.repo, localState: local, watched: current.watched)
            : current);
      }
      if (!mounted) return;
      setState(() => _items = next);
      _toast('Repo linked to MobileCode workspace.');
    } on Object catch (error) {
      _toast(_compact(error.toString(), 140), isError: true);
    }
  }

  Future<void> _cloneWorkspace(GitHubRepoHubItem item) async {
    final key = item.key;
    if (_cloningKeys.contains(key)) return;

    setState(() => _cloningKeys = {..._cloningKeys, key});
    GitHubRepoCloneTarget? cloneTarget;
    try {
      await _runtimeManager.initialize();
      final capabilities = await _runtimeManager.capabilities();
      if (!capabilities.git) {
        final local = await _hub.ensureRemoteLinkedWorkspace(item.repo);
        final next = <GitHubRepoHubItem>[];
        for (final current in _items) {
          next.add(current.key == key
              ? GitHubRepoHubItem(
                  repo: current.repo,
                  localState: local,
                  watched: current.watched,
                )
              : current);
        }
        if (!mounted) return;
        setState(() => _items = next);
        _toast(
          '当前 runtime 没有 git，已改为 Remote-linked 工作区；可先用 Files/API 提交，安装 Helper/Termux git 后再做完整克隆。',
        );
        return;
      }

      final provider = _runtimeManager.activeProvider;
      if (provider is TermuxDaemonProvider) {
        var workspaceRoot = provider.workspaceRoot?.trim();
        if (workspaceRoot == null || workspaceRoot.isEmpty) {
          final pwdResult = await _runtimeManager.execute(
            'pwd',
            timeout: const Duration(seconds: 10),
          );
          if (pwdResult.success) {
            workspaceRoot = pwdResult.stdout.trim();
          }
        }
        if (workspaceRoot == null || workspaceRoot.isEmpty) {
          throw StateError('Termux daemon did not report a workspaceRoot.');
        }
        final runtimePath = _hub.runtimeClonePathFor(item.repo, workspaceRoot);
        final runtimeParent = p.posix.dirname(runtimePath);
        final mkdirResult = await _runtimeManager.execute(
          'mkdir -p ${_shellArg(runtimeParent)}',
          timeout: const Duration(seconds: 20),
        );
        if (!mkdirResult.success) {
          throw StateError(_cloneFailureMessage(mkdirResult));
        }
        final existing = await _runtimeManager.execute(
          'git -C ${_shellArg(runtimePath)} status --short',
          timeout: const Duration(seconds: 20),
        );
        if (!existing.success) {
          final cloneUrl = item.repo.cloneUrl ?? '${item.repo.webUrl}.git';
          final branch = item.repo.defaultBranch.trim();
          final command = branch.isEmpty
              ? 'git clone ${_shellArg(cloneUrl)} ${_shellArg(runtimePath)}'
              : 'git clone --branch ${_shellArg(branch)} --single-branch '
                  '${_shellArg(cloneUrl)} ${_shellArg(runtimePath)}';
          final result = await _runtimeManager.execute(
            command,
            timeout: const Duration(minutes: 5),
          );
          if (!result.success) {
            throw StateError(_cloneFailureMessage(result));
          }
        }

        final local = await _hub.ensureRuntimeGitWorkspace(item.repo, runtimePath: runtimePath);
        final next = <GitHubRepoHubItem>[];
        for (final current in _items) {
          next.add(current.key == key
              ? GitHubRepoHubItem(
                  repo: current.repo,
                  localState: local,
                  watched: current.watched,
                )
              : current);
        }
        if (!mounted) return;
        setState(() => _items = next);
        _toast('Repo cloned through Termux git: $runtimePath');
        return;
      }

      final target = await _hub.prepareCloneTarget(item.repo);
      cloneTarget = target;
      final cloneUrl = item.repo.cloneUrl ?? '${item.repo.webUrl}.git';
      final branch = item.repo.defaultBranch.trim();
      final command = branch.isEmpty
          ? 'git clone ${_shellArg(cloneUrl)} ${_shellArg(target.clonePath)}'
          : 'git clone --branch ${_shellArg(branch)} --single-branch '
              '${_shellArg(cloneUrl)} ${_shellArg(target.clonePath)}';
      final result = await _runtimeManager.execute(
        command,
        timeout: const Duration(minutes: 5),
      );
      if (!result.success) {
        throw StateError(_cloneFailureMessage(result));
      }

      final local = await _hub.completeCloneTarget(item.repo, target);
      final next = <GitHubRepoHubItem>[];
      for (final current in _items) {
        next.add(current.key == key
            ? GitHubRepoHubItem(
                repo: current.repo,
                localState: local,
                watched: current.watched,
              )
            : current);
      }
      if (!mounted) return;
      setState(() => _items = next);
      _toast('Repo cloned to phone workspace.');
    } on Object catch (error) {
      final target = cloneTarget;
      if (target != null) {
        await _hub.cleanupCloneTarget(target);
      }
      if (!mounted) return;
      _toast(_friendlyCloneError(error), isError: true);
    } finally {
      if (mounted) {
        setState(() => _cloningKeys = {..._cloningKeys}..remove(key));
      }
    }
  }

  Future<void> _openUrl(String? url, String label) async {
    if (url == null || url.isEmpty) return;
    final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!mounted) return;
    _toast(opened ? 'Opened $label.' : 'Could not open $label.', isError: !opened);
  }

  Future<void> _openPages(GitHubRepo repo) async {
    await _openUrl(_pagesUrlFor(repo), 'GitHub Pages');
  }

  void _openRepoChat(GitHubRepoHubItem item) {
    Navigator.of(context).pop(
      GitHubRepoChatRequest(
        repoFullName: item.repo.fullName,
        repoUrl: item.repo.webUrl,
        pagesUrl: item.repo.hasPages ? _pagesUrlFor(item.repo) : null,
        actionsUrl: '${item.repo.webUrl}/actions',
        workspaceMode: _repoWorkspaceModeLabel(item.localState),
        workspacePath: item.localState.exists ? item.localState.path : null,
        prompt: _repoChatPrompt(item),
      ),
    );
  }

  Future<void> _copy(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    _toast('$label copied.');
  }

  Future<void> _installDiscoveryRepo(GitHubRepoHubItem item) async {
    if (_source != 'skill' && _source != 'mcp') return;
    final key = '${_source}:${item.key}';
    if (_installingKeys.contains(key)) return;
    setState(() => _installingKeys = {..._installingKeys, key});
    try {
      await _skillManager.initialize();
      if (_source == 'skill') {
        final skill = await _skillManager.previewSkillInstallFromRepo(item.repo.webUrl);
        if (!mounted) return;
        final ok = await _showSkillInstallReview(skill);
        if (ok == true) {
          await _skillManager.install(skill);
          if (!mounted) return;
          _toast('Skill 已装载: ${skill.name}');
          setState(() {});
        }
        return;
      }

      final candidate = await _skillManager.previewMcpInstallFromRepo(
        fullName: item.repo.fullName,
        repoUrl: item.repo.webUrl,
        name: item.repo.name,
        description: item.repo.description,
      );
      if (!mounted) return;
      final ok = await _showMcpInstallReview(candidate);
      if (ok == true) {
        await _skillManager.registerReviewedMcpCandidate(candidate);
        if (!mounted) return;
        _toast('MCP 候选已登记，默认未启用: ${candidate.name}');
        setState(() {});
      }
    } on Object catch (error) {
      if (!mounted) return;
      _toast(_compact(error.toString(), 180), isError: true);
    } finally {
      if (mounted) {
        setState(() => _installingKeys = {..._installingKeys}..remove(key));
      }
    }
  }

  Future<bool?> _showSkillInstallReview(Skill skill) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _panel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(18, 14, 18, MediaQuery.of(context).viewInsets.bottom + 18),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(color: _line, borderRadius: BorderRadius.circular(99)),
                ),
              ),
              const SizedBox(height: 14),
              const Text('审核并装载 Skill', style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 18)),
              const SizedBox(height: 8),
              Text(skill.name, style: const TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 15)),
              const SizedBox(height: 4),
              Text(skill.description, style: const TextStyle(color: _muted, height: 1.35)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  _HubPill(label: skill.version, icon: Icons.sell_outlined, color: _blue),
                  _HubPill(label: skill.author, icon: Icons.person_outline, color: _violet),
                  _HubPill(label: skill.source.displayName, icon: Icons.source_outlined, color: _mint),
                  if (skill.actions.isEmpty && skill.prompts.isEmpty)
                    const _HubPill(label: 'metadata-only', icon: Icons.warning_amber_outlined, color: _amber),
                ],
              ),
              if (skill.githubUrl != null) ...[
                const SizedBox(height: 10),
                SelectableText(skill.githubUrl!, style: const TextStyle(color: _faint, fontSize: 12)),
              ],
              const SizedBox(height: 12),
              const _InlineInfoBox(
                icon: Icons.verified_user_outlined,
                color: _amber,
                title: '先审核，再装载',
                detail: 'MobileCode 先导入 manifest 或 metadata。启用和运行仍由用户控制。',
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(true),
                      icon: const Icon(Icons.download_done_outlined),
                      label: const Text('装载已审核 Skill'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool?> _showMcpInstallReview(McpServer server) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _panel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(18, 14, 18, MediaQuery.of(context).viewInsets.bottom + 18),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(color: _line, borderRadius: BorderRadius.circular(99)),
                ),
              ),
              const SizedBox(height: 14),
              const Text('Review MCP candidate', style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 18)),
              const SizedBox(height: 8),
              Text(server.name, style: const TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 15)),
              const SizedBox(height: 4),
              Text(server.description ?? 'No description', style: const TextStyle(color: _muted, height: 1.35)),
              const SizedBox(height: 10),
              _CodeLine(label: 'type', value: server.type),
              _CodeLine(label: 'command', value: server.command.isEmpty ? '(not inferred)' : server.command),
              const SizedBox(height: 12),
              const _InlineInfoBox(
                icon: Icons.power_settings_new_outlined,
                color: _amber,
                title: 'Registered disabled',
                detail: 'This only stores a disabled MCP candidate. MobileCode will not start a process from GitHub discovery.',
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(true),
                      icon: const Icon(Icons.playlist_add_check_outlined),
                      label: const Text('登记为未启用 MCP'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _analyzeGitHubKnowledge() async {
    if (!_authenticated || _analyzingKnowledge) {
      _toast('GitHub access is required before analysis.', isError: true);
      return;
    }
    setState(() => _analyzingKnowledge = true);
    try {
      await _memory.init();
      await _roles.initialize();
      final digest = await _repoKnowledge.analyzeWatchedAndOwnerRepos(_hub);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: _panel,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (_) => _RepoKnowledgeDigestSheet(
          digest: digest,
          roleLibrary: _roles,
          memory: _memory,
          onMessage: _toast,
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      _toast(_compact(error.toString(), 180), isError: true);
    } finally {
      if (mounted) setState(() => _analyzingKnowledge = false);
    }
  }

  void _showActions(GitHubRepo repo) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _panel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
      builder: (_) => _RepoActionsSheet(
        repo: repo,
        hub: _hub,
        onOpenUrl: _openUrl,
        onMessage: _toast,
      ),
    );
  }

  void _showWorkspace(GitHubRepo repo) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _panel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
      builder: (_) => _RepoWorkspaceSheet(
        repo: repo,
        hub: _hub,
        runtimeManager: _runtimeManager,
        onMessage: _toast,
      ),
    );
  }

  void _toast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? _rose : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleItems;
    final languageOptions = <String, String>{};
    for (final item in _items) {
      final language = item.repo.language?.trim();
      if (language == null || language.isEmpty) continue;
      languageOptions.putIfAbsent(language.toLowerCase(), () => language);
    }
    final languages = languageOptions.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('GitHub Repo Hub'),
        actions: [
          IconButton(
            tooltip: 'Downloads / Shared folders',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const DownloadsSharedFoldersScreen()),
            ),
            icon: const Icon(Icons.folder_shared_outlined),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _refresh,
            icon: _loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          const _HubHeader(),
          const SizedBox(height: 12),
          if (_authenticated) ...[
            _HubAccountPanel(
              hub: _hub,
              currentUser: _hub.currentUser,
              accounts: _hub.accountList,
              source: _source,
              analyzing: _analyzingKnowledge,
              onSwitch: (username) => unawaited(_switchAccount(username)),
              onAnalyze: () => unawaited(_analyzeGitHubKnowledge()),
            ),
            const SizedBox(height: 12),
          ] else ...[
            _AuthPanel(onLogin: _openLogin),
            const SizedBox(height: 12),
          ],
          _HubPanel(
            child: Column(
              children: [
                TextField(
                  controller: _ownerController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => unawaited(_refresh()),
                  decoration: InputDecoration(
                    labelText: _source == 'owner' ? 'GitHub user / org' : _sourceSearchLabel(_source),
                    hintText: _source == 'owner'
                        ? (_hub.currentUser == null ? 'Type Harzva, flutter, vercel...' : 'Blank = ${_hub.currentUser}')
                        : _sourceSearchHint(_source),
                    prefixIcon: Icon(_source == 'owner' ? Icons.account_circle_outlined : Icons.public_outlined),
                    suffixIcon: IconButton(
                      tooltip: _source == 'owner' ? 'Load repos' : 'Search GitHub',
                      onPressed: _loading ? null : _refresh,
                      icon: const Icon(Icons.travel_explore_outlined),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _FilterChip(label: 'Any repo', value: 'repo', selected: _source == 'repo', onSelected: _setSource),
                    _FilterChip(label: 'Owner repos', value: 'owner', selected: _source == 'owner', onSelected: _setSource),
                    _FilterChip(label: 'Skill', value: 'skill', selected: _source == 'skill', onSelected: _setSource),
                    _FilterChip(label: 'MCP', value: 'mcp', selected: _source == 'mcp', onSelected: _setSource),
                    _FilterChip(label: 'Release', value: 'release', selected: _source == 'release', onSelected: _setSource),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _sourceScopeCopy(_source),
                  style: const TextStyle(color: _muted, fontSize: 11.5, height: 1.35),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    labelText: 'Filter loaded cards',
                    hintText: 'name, description, language',
                    prefixIcon: Icon(Icons.search_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _sort,
                  decoration: const InputDecoration(labelText: 'Sort'),
                  items: const [
                    DropdownMenuItem(value: 'pushed', child: Text('Recently pushed')),
                    DropdownMenuItem(value: 'updated', child: Text('Recently updated')),
                    DropdownMenuItem(value: 'created', child: Text('Recently created')),
                    DropdownMenuItem(value: 'full_name', child: Text('Name')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _sort = value);
                    unawaited(_refresh());
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: languageOptions.containsKey(_languageFilter) ? _languageFilter : 'all',
                  decoration: const InputDecoration(labelText: 'Language'),
                  items: [
                    const DropdownMenuItem(value: 'all', child: Text('All languages')),
                    for (final language in languages) DropdownMenuItem(value: language.key, child: Text(language.value)),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _languageFilter = value);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _FilterChip(label: 'All', value: 'all', selected: _filter == 'all', onSelected: _setFilter),
              _FilterChip(label: '关注', value: 'watched', selected: _filter == 'watched', onSelected: _setFilter),
              _FilterChip(label: 'On phone', value: 'local', selected: _filter == 'local', onSelected: _setFilter),
              _FilterChip(label: 'Git', value: 'git', selected: _filter == 'git', onSelected: _setFilter),
              _FilterChip(label: 'Pages', value: 'pages', selected: _filter == 'pages', onSelected: _setFilter),
            ],
          ),
          const SizedBox(height: 10),
          _HubStats(total: _items.length, visible: visible.length),
          const SizedBox(height: 12),
          if (_notice != null)
            _HubPanel(
              borderColor: _amber,
              child: Text(_notice!, style: const TextStyle(color: _amber, height: 1.35)),
            ),
          if (_error != null)
            _HubPanel(
              borderColor: _rose,
              child: Text(_error!, style: const TextStyle(color: _rose, height: 1.35)),
            ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (visible.isEmpty)
            _HubPanel(
              child: Text(_emptyStateMessage(), style: const TextStyle(color: _muted)),
            )
          else
            for (final item in visible) ...[
              _RepoHubCard(
                item: item,
                hub: _hub,
                currentUser: _hub.currentUser,
                source: _source,
                cloning: _cloningKeys.contains(item.key),
                installing: _installingKeys.contains('${_source}:${item.key}'),
                installLabel: _installLabel(item),
                onWatched: (value) => unawaited(_setWatched(item, value)),
                onLinkWorkspace: () => unawaited(_linkWorkspace(item)),
                onCloneWorkspace: () => unawaited(_cloneWorkspace(item)),
                onInstall: () => unawaited(_installDiscoveryRepo(item)),
                onOpenRepo: () => unawaited(_openUrl(item.repo.webUrl, 'repository')),
                onOpenPages: item.repo.hasPages ? () => unawaited(_openPages(item.repo)) : null,
                onOpenChat: () => _openRepoChat(item),
                onOpenUrl: (url, label) => unawaited(_openUrl(url, label)),
                onCopyRepoUrl: () => unawaited(_copy(item.repo.webUrl, 'GitHub URL')),
                onCopyPath: () => unawaited(_copy(item.localState.path, 'Workspace path')),
                onActions: () => _showActions(item.repo),
                onWorkspace: () => _showWorkspace(item.repo),
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }

  String _emptyStateMessage() {
    if (_notice != null && !_hasLoaded) return _notice!;
    if (_items.isNotEmpty && _visibleItems.isEmpty) {
      return 'Loaded repositories are hidden by the current filter. Clear search text, language, or status chips.';
    }
    if (_source == 'owner') {
      final owner = _ownerController.text.trim();
      if (owner.isEmpty && !_authenticated) {
        return 'Type a GitHub user/org to browse public repos, or add GitHub access to load your own repos.';
      }
      if (owner.isEmpty) return 'No repositories were returned for the active GitHub account.';
      return 'No public repositories were returned for $owner.';
    }
    if (!_hasLoaded) return 'Type a query or tap search to discover public GitHub repositories.';
    return 'No public repositories matched this GitHub search.';
  }

  String? _installLabel(GitHubRepoHubItem item) {
    if (_source != 'skill' && _source != 'mcp') return null;
    if (!_skillManager.isInitialized) return _source == 'skill' ? '装载' : '登记';
    try {
      if (_source == 'skill') {
        return _skillManager.isGitHubSkillInstalled(item.repo.webUrl) ? '已装载' : '装载';
      }
      return _skillManager.isMcpRepoRegistered(item.repo.fullName) ? '已登记' : '登记';
    } on Object {
      return _source == 'skill' ? '装载' : '登记';
    }
  }

  void _setFilter(String value) {
    setState(() => _filter = value);
  }

  String _friendlyGitHubError(Object error) {
    if (error is GitHubDeepException) {
      final status = error.statusCode;
      if (status == 401) {
        return 'GitHub token 失效或无效。公开搜索仍可用；账号仓库、Pages、Actions 操作需要重新登录。';
      }
      if (status == 403) {
        return 'GitHub 返回 403。可能是匿名 rate limit、token scope 不足，或该仓库不允许当前账号访问。';
      }
      if (status == 404) {
        return _source == 'owner'
            ? '没有找到这个 owner/org 的公开仓库，或该账号不可见。'
            : '没有找到可公开访问的仓库资源。';
      }
      return _compact('GitHub ${status ?? ''}: ${error.message}', 180);
    }
    return _compact(error.toString(), 180);
  }

  void _setSource(String value) {
    setState(() {
      _source = value;
      _filter = 'all';
      _languageFilter = 'all';
    });
    unawaited(_refresh());
  }

  Future<void> _switchAccount(String username) async {
    if (username == _hub.currentUser) return;
    final ok = await _hub.switchAccount(username);
    if (!mounted) return;
    _toast(ok ? 'Switched GitHub account to $username.' : 'Could not switch GitHub account.', isError: !ok);
    if (ok) await _refresh();
  }
}

class _HubHeader extends StatelessWidget {
  const _HubHeader();

  @override
  Widget build(BuildContext context) {
    return _HubPanel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _blue.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _line),
            ),
            child: Center(
              child: SvgPicture.asset(
                'assets/icons/github-mark-24.svg',
                width: 24,
                height: 24,
                colorFilter: const ColorFilter.mode(_blue, BlendMode.srcIn),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('GitHub-first mobile workspace', style: TextStyle(color: _text, fontSize: 16, fontWeight: FontWeight.w900)),
                SizedBox(height: 4),
                Text(
                  'Use GitHub as the remote project index and build layer. The phone keeps light files, previews, watchlists, Pages, and Actions status.',
                  style: TextStyle(color: _muted, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthPanel extends StatelessWidget {
  const _AuthPanel({required this.onLogin});

  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return _HubPanel(
      borderColor: _amber,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('GitHub access optional', style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 6),
          const Text(
            'Public search works without login. Add access when you want private repos, Pages publishing, Actions dispatch, or file commits.',
            style: TextStyle(color: _muted, height: 1.35),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onLogin,
            icon: const Icon(Icons.login_outlined),
            label: const Text('Add GitHub access'),
          ),
        ],
      ),
    );
  }
}

class _HubAccountPanel extends StatelessWidget {
  const _HubAccountPanel({
    required this.hub,
    required this.currentUser,
    required this.accounts,
    required this.source,
    required this.analyzing,
    required this.onSwitch,
    required this.onAnalyze,
  });

  final GitHubRepoHubService hub;
  final String? currentUser;
  final List<String> accounts;
  final String source;
  final bool analyzing;
  final ValueChanged<String> onSwitch;
  final VoidCallback onAnalyze;

  @override
  Widget build(BuildContext context) {
    final active = currentUser;
    return _HubPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.switch_account_outlined, color: _blue, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  active == null ? 'GitHub account not selected' : 'Operations use @$active',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _text, fontSize: 14, fontWeight: FontWeight.w900),
                ),
              ),
              _HubPill(
                label: source == 'owner' ? 'Managed lane' : 'Discovery lane',
                icon: source == 'owner' ? Icons.verified_user_outlined : Icons.travel_explore_outlined,
                color: source == 'owner' ? _mint : _amber,
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Repo writes, Pages, and Actions always run through the active account. External search results stay read-only until the token has write access or you fork the repo.',
            style: TextStyle(color: _muted, fontSize: 11.5, height: 1.35),
          ),
          if (active != null) ...[
            const SizedBox(height: 8),
            FutureBuilder<List<String>>(
              future: hub.loadTokenScopes(username: active),
              builder: (context, snapshot) {
                final scopes = snapshot.data ?? const <String>[];
                final label = snapshot.connectionState == ConnectionState.waiting
                    ? 'checking scopes'
                    : scopes.isEmpty
                        ? 'scopes hidden or fine-grained'
                        : scopes.take(4).join(', ');
                return _HubPill(label: label, icon: Icons.key_outlined, color: scopes.isEmpty ? _faint : _violet);
              },
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: analyzing ? null : onAnalyze,
                icon: analyzing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome_outlined, size: 18),
                label: Text(analyzing ? 'Analyzing repositories...' : 'Analyze my GitHub'),
              ),
            ),
          ],
          if (accounts.length > 1) ...[
            const SizedBox(height: 9),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final account in accounts)
                  ChoiceChip(
                    selected: account == active,
                    label: Text('@$account'),
                    avatar: Icon(account == active ? Icons.check_circle_outline : Icons.account_circle_outlined, size: 16),
                    onSelected: account == active ? null : (_) => onSwitch(account),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _HubStats extends StatelessWidget {
  const _HubStats({required this.total, required this.visible});

  final int total;
  final int visible;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _HubPill(label: '$visible shown', icon: Icons.view_list_outlined, color: _blue),
        const SizedBox(width: 8),
        _HubPill(label: '$total loaded', icon: Icons.cloud_done_outlined, color: _mint),
      ],
    );
  }
}

class _RepoRelation {
  const _RepoRelation({
    required this.label,
    required this.detail,
    required this.icon,
    required this.color,
  });

  final String label;
  final String detail;
  final IconData icon;
  final Color color;
}

_RepoRelation _repoRelation(GitHubRepo repo, String? currentUser, String source) {
  final activeOwner = currentUser?.trim().toLowerCase();
  final repoOwner = repo.owner.trim().toLowerCase();
  if (activeOwner != null && activeOwner.isNotEmpty && activeOwner == repoOwner) {
    return const _RepoRelation(
      label: 'Your account',
      detail: 'Managed with the active GitHub account; commit, Pages, and Actions are expected to work when scopes are valid.',
      icon: Icons.verified_user_outlined,
      color: _mint,
    );
  }
  if (source == 'owner') {
    return const _RepoRelation(
      label: 'Owner/org',
      detail: 'Listed from the chosen owner or organization. Write actions require collaborator or organization permission.',
      icon: Icons.groups_2_outlined,
      color: _blue,
    );
  }
  return const _RepoRelation(
    label: 'External',
    detail: 'Discovered from GitHub search. Treat as read-only unless you fork it or the active token has write access.',
    icon: Icons.travel_explore_outlined,
    color: _amber,
  );
}

class _RepoHubCard extends StatelessWidget {
  const _RepoHubCard({
    required this.item,
    required this.hub,
    required this.currentUser,
    required this.source,
    required this.cloning,
    required this.installing,
    required this.installLabel,
    required this.onWatched,
    required this.onLinkWorkspace,
    required this.onCloneWorkspace,
    required this.onInstall,
    required this.onOpenRepo,
    required this.onOpenChat,
    required this.onOpenUrl,
    required this.onCopyRepoUrl,
    required this.onCopyPath,
    required this.onActions,
    required this.onWorkspace,
    this.onOpenPages,
  });

  final GitHubRepoHubItem item;
  final GitHubRepoHubService hub;
  final String? currentUser;
  final String source;
  final bool cloning;
  final bool installing;
  final String? installLabel;
  final ValueChanged<bool> onWatched;
  final VoidCallback onLinkWorkspace;
  final VoidCallback onCloneWorkspace;
  final VoidCallback onInstall;
  final VoidCallback onOpenRepo;
  final VoidCallback onOpenChat;
  final void Function(String url, String label) onOpenUrl;
  final VoidCallback onCopyRepoUrl;
  final VoidCallback onCopyPath;
  final VoidCallback onActions;
  final VoidCallback onWorkspace;
  final VoidCallback? onOpenPages;

  @override
  Widget build(BuildContext context) {
    final repo = item.repo;
    final local = item.localState;
    final relation = _repoRelation(repo, currentUser, source);
    final hasPhoneWorkspace = local.exists || local.remoteLinked || local.hasGit;
    final localDetail = hasPhoneWorkspace
        ? 'Pushed ${_timeAgo(repo.pushedAt)} · ${local.statusLabel} · ${local.path}'
        : 'Pushed ${_timeAgo(repo.pushedAt)} · No phone workspace yet';
    final localColor = local.hasGit
        ? _mint
        : local.remoteLinked
            ? _blue
            : local.exists
                ? _amber
                : _faint;
    return _HubPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: item.watched,
                onChanged: (value) => onWatched(value ?? false),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(repo.fullName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 15)),
                    if (repo.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(repo.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, height: 1.3)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _HubPill(label: repo.isPrivate ? 'Private' : 'Public', icon: repo.isPrivate ? Icons.lock_outline : Icons.public_outlined, color: repo.isPrivate ? _amber : _mint),
              if (repo.language != null) _HubPill(label: repo.language!, icon: Icons.code_outlined, color: _violet),
              _HubPill(label: '${repo.stars} stars', icon: Icons.star_border_outlined, color: _amber),
              _HubPill(label: repo.defaultBranch, icon: Icons.account_tree_outlined, color: _blue),
              _HubPill(label: relation.label, icon: relation.icon, color: relation.color),
              if (repo.hasPages) _HubPill(label: 'Pages', icon: Icons.web_outlined, color: _mint, onTap: onOpenPages),
              _HubPill(label: local.statusLabel, icon: local.hasGit ? Icons.call_split_outlined : Icons.folder_open_outlined, color: localColor),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            localDetail,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _faint, fontSize: 11, height: 1.3),
          ),
          if (!local.hasGit) ...[
            const SizedBox(height: 5),
            Text(
              '${relation.detail} ${local.modeDescription}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _muted, fontSize: 11, height: 1.3),
            ),
          ],
          if (source == 'release') ...[
            const SizedBox(height: 10),
            _ReleaseAssetsPreview(
              hub: hub,
              repo: repo,
              onOpenUrl: onOpenUrl,
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (installLabel != null)
                FilledButton.icon(
                  onPressed: installing || installLabel == '已装载' || installLabel == '已登记'
                      ? null
                      : onInstall,
                  icon: installing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(
                          installLabel == '已登记' || installLabel == '已装载'
                              ? Icons.check_circle_outline
                              : Icons.download_outlined,
                          size: 16,
                        ),
                  label: Text(installing ? (installLabel == '登记' ? '登记中...' : '装载中...') : installLabel!),
                ),
              OutlinedButton.icon(
                onPressed: onLinkWorkspace,
                icon: const Icon(Icons.add_to_drive_outlined, size: 16),
                label: Text(local.exists ? '刷新本机链接' : '创建手机工作区'),
              ),
              if (!local.hasGit)
                OutlinedButton.icon(
                  onPressed: cloning ? null : onCloneWorkspace,
                  icon: const Icon(Icons.download_for_offline_outlined, size: 16),
                  label: Text(cloning ? 'Cloning...' : 'Git 克隆'),
                ),
              OutlinedButton.icon(
                onPressed: onOpenChat,
                icon: const Icon(Icons.chat_bubble_outline, size: 16),
                label: const Text('Open chat'),
              ),
              OutlinedButton.icon(
                onPressed: onActions,
                icon: const Icon(Icons.play_circle_outline, size: 16),
                label: const Text('Actions'),
              ),
              OutlinedButton.icon(
                onPressed: onWorkspace,
                icon: Icon(local.runtimeGit ? Icons.sync_alt_outlined : Icons.folder_copy_outlined, size: 16),
                label: Text(local.runtimeGit ? 'Runtime 文件' : 'Files'),
              ),
              OutlinedButton.icon(
                onPressed: onOpenRepo,
                icon: const Icon(Icons.open_in_new_outlined, size: 16),
                label: const Text('仓库'),
              ),
              OutlinedButton.icon(
                onPressed: onCopyRepoUrl,
                icon: const Icon(Icons.link_outlined, size: 16),
                label: const Text('复制地址'),
              ),
              OutlinedButton.icon(
                onPressed: hasPhoneWorkspace ? onCopyPath : null,
                icon: const Icon(Icons.copy_outlined, size: 16),
                label: Text(hasPhoneWorkspace ? '路径' : '未创建路径'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReleaseAssetsPreview extends StatelessWidget {
  const _ReleaseAssetsPreview({
    required this.hub,
    required this.repo,
    required this.onOpenUrl,
  });

  final GitHubRepoHubService hub;
  final GitHubRepo repo;
  final void Function(String url, String label) onOpenUrl;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<GitHubReleaseSummary?>(
      future: hub.loadLatestReleaseSummary(repo),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _InlineInfoBox(
            icon: Icons.new_releases_outlined,
            color: _blue,
            title: 'Reading latest release...',
            detail: 'Checking GitHub Releases for APK/zip assets.',
          );
        }
        if (snapshot.hasError) {
          return _InlineInfoBox(
            icon: Icons.error_outline,
            color: _rose,
            title: 'Release assets unavailable',
            detail: _compact(snapshot.error.toString(), 130),
          );
        }
        final release = snapshot.data;
        if (release == null) {
          return const _InlineInfoBox(
            icon: Icons.inventory_2_outlined,
            color: _faint,
            title: 'No releases yet',
            detail: 'This repo has no GitHub Releases visible to the active account.',
          );
        }
        final assets = release.buildAssets;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _blue.withOpacity(0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _blue.withOpacity(0.18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.new_releases_outlined, color: _blue, size: 16),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      '${release.tagName} · ${assets.length} APK/zip assets',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _text, fontSize: 12, fontWeight: FontWeight.w900),
                    ),
                  ),
                  if (release.releaseUrl.isNotEmpty)
                    TextButton(
                      onPressed: () => onOpenUrl(release.releaseUrl, 'release'),
                      child: const Text('Release'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              if (assets.isEmpty)
                const Text(
                  'Latest release exists, but no APK/zip artifact is attached.',
                  style: TextStyle(color: _muted, fontSize: 11.5, height: 1.3),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final asset in assets.take(4))
                      _ReleaseAssetChip(
                        asset: asset,
                        onTap: () => onOpenUrl(asset.downloadUrl, asset.name),
                      ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _InlineInfoBox extends StatelessWidget {
  const _InlineInfoBox({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.20)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: _text, fontSize: 12, fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 11, height: 1.25)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CodeLine extends StatelessWidget {
  const _CodeLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78,
            child: Text(label, style: const TextStyle(color: _faint, fontSize: 12, fontWeight: FontWeight.w800)),
          ),
          Expanded(
            child: SelectableText(value, style: const TextStyle(color: _text, fontSize: 12.5, height: 1.3)),
          ),
        ],
      ),
    );
  }
}

class _RepoKnowledgeDigestSheet extends StatefulWidget {
  const _RepoKnowledgeDigestSheet({
    required this.digest,
    required this.roleLibrary,
    required this.memory,
    required this.onMessage,
  });

  final RepoKnowledgeDigest digest;
  final RoleLibraryService roleLibrary;
  final MemoryService memory;
  final void Function(String message, {bool isError}) onMessage;

  @override
  State<_RepoKnowledgeDigestSheet> createState() => _RepoKnowledgeDigestSheetState();
}

class _RepoKnowledgeDigestSheetState extends State<_RepoKnowledgeDigestSheet> {
  final Set<String> _acceptedRoles = {};
  final Set<String> _ignoredRoles = {};
  final Set<String> _acceptedRules = {};
  final Set<String> _ignoredRules = {};

  @override
  Widget build(BuildContext context) {
    final digest = widget.digest;
    return FractionallySizedBox(
      heightFactor: 0.92,
      child: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(color: _line, borderRadius: BorderRadius.circular(99)),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.auto_awesome_outlined, color: _violet, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'GitHub repository intelligence',
                    style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 18),
                  ),
                ),
                _HubPill(
                  label: digest.usedProvider ? 'AI summary' : 'heuristic',
                  icon: digest.usedProvider ? Icons.cloud_done_outlined : Icons.offline_bolt_outlined,
                  color: digest.usedProvider ? _mint : _amber,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(digest.summary, style: const TextStyle(color: _muted, height: 1.35)),
            if (digest.fallbackReason != null) ...[
              const SizedBox(height: 10),
              _InlineInfoBox(
                icon: Icons.info_outline,
                color: _amber,
                title: 'Local fallback',
                detail: digest.fallbackReason!,
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                _HubPill(label: '${digest.analyzedRepos.length} repos', icon: Icons.folder_copy_outlined, color: _blue),
                for (final stack in digest.techStacks.take(6))
                  _HubPill(label: stack, icon: Icons.code_outlined, color: _violet),
              ],
            ),
            if (digest.analyzedRepos.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Evidence repos', style: TextStyle(color: _text, fontWeight: FontWeight.w900)),
              const SizedBox(height: 7),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final repo in digest.analyzedRepos.take(8))
                    _HubPill(label: repo, icon: Icons.folder_outlined, color: _faint),
                ],
              ),
            ],
            const SizedBox(height: 18),
            _DigestSectionTitle(
              title: 'Suggested Roles',
              subtitle: '保存前不会写入 Roles。',
              icon: Icons.groups_2_outlined,
              color: _violet,
            ),
            if (digest.roleProposals.isEmpty)
              const _InlineInfoBox(
                icon: Icons.info_outline,
                color: _faint,
                title: 'No role suggestion',
                detail: 'Repository evidence was too thin to suggest a useful role.',
              )
            else
              for (final proposal in digest.roleProposals)
                _RoleProposalReviewCard(
                  proposal: proposal,
                  accepted: _acceptedRoles.contains(proposal.proposalId),
                  ignored: _ignoredRoles.contains(proposal.proposalId),
                  onAccept: () => _acceptRole(proposal),
                  onEditAccept: () => _editAndAcceptRole(proposal),
                  onIgnore: () => setState(() => _ignoredRoles.add(proposal.proposalId)),
                ),
            const SizedBox(height: 18),
            _DigestSectionTitle(
              title: 'Suggested Memory Rules',
              subtitle: '保存到 App Memory，不修改仓库文件。',
              icon: Icons.psychology_alt_outlined,
              color: _mint,
            ),
            if (digest.memoryProposals.isEmpty)
              const _InlineInfoBox(
                icon: Icons.info_outline,
                color: _faint,
                title: 'No memory rule suggestion',
                detail: 'Repository evidence was too thin to create a durable rule.',
              )
            else
              for (final proposal in digest.memoryProposals)
                _MemoryRuleProposalReviewCard(
                  proposal: proposal,
                  accepted: _acceptedRules.contains(proposal.proposalId),
                  ignored: _ignoredRules.contains(proposal.proposalId),
                  onAccept: () => _acceptRule(proposal),
                  onEditAccept: () => _editAndAcceptRule(proposal),
                  onIgnore: () => setState(() => _ignoredRules.add(proposal.proposalId)),
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _acceptRole(RoleProposal proposal) async {
    await widget.roleLibrary.initialize();
    await widget.roleLibrary.upsertCustomRole(proposal.role);
    setState(() => _acceptedRoles.add(proposal.proposalId));
    widget.onMessage('Role saved: ${proposal.role.name}');
  }

  Future<void> _editAndAcceptRole(RoleProposal proposal) async {
    final edited = await showModalBottomSheet<MobileCodeRole>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _panel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _RoleProposalEditSheet(role: proposal.role),
    );
    if (edited == null) return;
    await widget.roleLibrary.initialize();
    await widget.roleLibrary.upsertCustomRole(edited);
    setState(() => _acceptedRoles.add(proposal.proposalId));
    widget.onMessage('Edited role saved: ${edited.name}');
  }

  Future<void> _acceptRule(MemoryRuleProposal proposal) async {
    await widget.memory.init();
    await widget.memory.upsertMemoryRule(proposal.rule);
    setState(() => _acceptedRules.add(proposal.proposalId));
    widget.onMessage('Memory rule saved: ${proposal.rule.title}');
  }

  Future<void> _editAndAcceptRule(MemoryRuleProposal proposal) async {
    final edited = await showModalBottomSheet<MemoryRule>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _panel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _MemoryRuleProposalEditSheet(rule: proposal.rule),
    );
    if (edited == null) return;
    await widget.memory.init();
    await widget.memory.upsertMemoryRule(edited);
    setState(() => _acceptedRules.add(proposal.proposalId));
    widget.onMessage('Edited memory rule saved: ${edited.title}');
  }
}

class _DigestSectionTitle extends StatelessWidget {
  const _DigestSectionTitle({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: color, size: 19),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 15)),
                Text(subtitle, style: const TextStyle(color: _muted, fontSize: 11.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleProposalReviewCard extends StatelessWidget {
  const _RoleProposalReviewCard({
    required this.proposal,
    required this.accepted,
    required this.ignored,
    required this.onAccept,
    required this.onEditAccept,
    required this.onIgnore,
  });

  final RoleProposal proposal;
  final bool accepted;
  final bool ignored;
  final Future<void> Function() onAccept;
  final Future<void> Function() onEditAccept;
  final VoidCallback onIgnore;

  @override
  Widget build(BuildContext context) {
    final role = proposal.role;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accepted ? _mint.withOpacity(0.07) : _bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accepted ? _mint.withOpacity(0.3) : _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.badge_outlined, color: _violet, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(role.name, style: const TextStyle(color: _text, fontWeight: FontWeight.w900)),
              ),
              if (accepted)
                const _HubPill(label: 'Saved', icon: Icons.check_circle_outline, color: _mint)
              else if (ignored)
                const _HubPill(label: 'Ignored', icon: Icons.visibility_off_outlined, color: _faint),
            ],
          ),
          const SizedBox(height: 6),
          Text(role.summary, style: const TextStyle(color: _muted, height: 1.3)),
          const SizedBox(height: 8),
          Text(proposal.rationale, style: const TextStyle(color: _faint, fontSize: 11.5, height: 1.3)),
          if (!accepted && !ignored) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onIgnore,
                    child: const Text('忽略'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: OutlinedButton.icon(
                    onPressed: () => unawaited(onEditAccept()),
                    icon: const Icon(Icons.edit_note_outlined, size: 16),
                    label: const Text('编辑后保存'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: () => unawaited(onAccept()),
                    icon: const Icon(Icons.library_add_check_outlined, size: 16),
                    label: const Text('保存到 Roles'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MemoryRuleProposalReviewCard extends StatelessWidget {
  const _MemoryRuleProposalReviewCard({
    required this.proposal,
    required this.accepted,
    required this.ignored,
    required this.onAccept,
    required this.onEditAccept,
    required this.onIgnore,
  });

  final MemoryRuleProposal proposal;
  final bool accepted;
  final bool ignored;
  final Future<void> Function() onAccept;
  final Future<void> Function() onEditAccept;
  final VoidCallback onIgnore;

  @override
  Widget build(BuildContext context) {
    final rule = proposal.rule;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accepted ? _mint.withOpacity(0.07) : _bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accepted ? _mint.withOpacity(0.3) : _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.rule_outlined, color: _mint, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(rule.title, style: const TextStyle(color: _text, fontWeight: FontWeight.w900)),
              ),
              if (accepted)
                const _HubPill(label: 'Saved', icon: Icons.check_circle_outline, color: _mint)
              else if (ignored)
                const _HubPill(label: 'Ignored', icon: Icons.visibility_off_outlined, color: _faint),
            ],
          ),
          const SizedBox(height: 6),
          Text(rule.rule, style: const TextStyle(color: _muted, height: 1.3)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _HubPill(label: rule.category, icon: Icons.label_outline, color: _blue),
              for (final repo in rule.evidenceRepos.take(3))
                _HubPill(label: repo, icon: Icons.folder_outlined, color: _faint),
            ],
          ),
          if (!accepted && !ignored) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onIgnore,
                    child: const Text('忽略'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: OutlinedButton.icon(
                    onPressed: () => unawaited(onEditAccept()),
                    icon: const Icon(Icons.edit_note_outlined, size: 16),
                    label: const Text('编辑后保存'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: () => unawaited(onAccept()),
                    icon: const Icon(Icons.library_add_check_outlined, size: 16),
                    label: const Text('保存到 Memory'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _RoleProposalEditSheet extends StatefulWidget {
  const _RoleProposalEditSheet({required this.role});

  final MobileCodeRole role;

  @override
  State<_RoleProposalEditSheet> createState() => _RoleProposalEditSheetState();
}

class _RoleProposalEditSheetState extends State<_RoleProposalEditSheet> {
  late final TextEditingController _name;
  late final TextEditingController _summary;
  late final TextEditingController _mission;
  late final TextEditingController _personality;
  late final TextEditingController _responsibilities;
  late final TextEditingController _guardrails;
  late final TextEditingController _successCriteria;
  late final TextEditingController _promptTemplate;
  String? _error;
  String? _polishNote;
  bool _polishing = false;

  @override
  void initState() {
    super.initState();
    final role = widget.role;
    _name = TextEditingController(text: role.name);
    _summary = TextEditingController(text: role.summary);
    _mission = TextEditingController(text: role.mission);
    _personality = TextEditingController(text: role.personality);
    _responsibilities = TextEditingController(text: _joinLines(role.responsibilities));
    _guardrails = TextEditingController(text: _joinLines(role.guardrails));
    _successCriteria = TextEditingController(text: _joinLines(role.successCriteria));
    _promptTemplate = TextEditingController(text: role.promptTemplate);
  }

  @override
  void dispose() {
    _name.dispose();
    _summary.dispose();
    _mission.dispose();
    _personality.dispose();
    _responsibilities.dispose();
    _guardrails.dispose();
    _successCriteria.dispose();
    _promptTemplate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.92,
      child: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(18, 14, 18, MediaQuery.of(context).viewInsets.bottom + 18),
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(color: _line, borderRadius: BorderRadius.circular(99)),
              ),
            ),
            const SizedBox(height: 14),
            const Text('Edit Role before saving', style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 6),
            const Text(
              '把建议角色改成你真正想长期使用的模板。保存后才会写入 Roles。',
              style: TextStyle(color: _muted, height: 1.35),
            ),
            const SizedBox(height: 12),
            _PolishActionBox(
              title: 'AI 润色标准化',
              detail: '先按你的想法粗改字段，再让模型整理成稳定的 Role Card；不可用时会用本地模板兜底。',
              note: _polishNote,
              polishing: _polishing,
              onPressed: _polish,
            ),
            const SizedBox(height: 14),
            _EditTextField(controller: _name, label: 'Role name', icon: Icons.badge_outlined),
            _EditTextField(controller: _summary, label: 'Summary', icon: Icons.short_text_outlined, maxLines: 2),
            _EditTextField(controller: _mission, label: 'Mission', icon: Icons.flag_outlined, maxLines: 3),
            _EditTextField(controller: _personality, label: 'Personality', icon: Icons.psychology_outlined, maxLines: 3),
            _EditTextField(
              controller: _responsibilities,
              label: 'Responsibilities',
              icon: Icons.checklist_outlined,
              maxLines: 5,
              helperText: '每行一条',
            ),
            _EditTextField(
              controller: _guardrails,
              label: 'Guardrails',
              icon: Icons.security_outlined,
              maxLines: 4,
              helperText: '每行一条',
            ),
            _EditTextField(
              controller: _successCriteria,
              label: 'Success criteria',
              icon: Icons.verified_outlined,
              maxLines: 4,
              helperText: '每行一条',
            ),
            _EditTextField(
              controller: _promptTemplate,
              label: 'Prompt template',
              icon: Icons.article_outlined,
              maxLines: 6,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: _rose, height: 1.3)),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _polishing ? null : _save,
                    icon: const Icon(Icons.library_add_check_outlined),
                    label: const Text('Save edited Role'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _polish() async {
    final draft = _draftRole();
    if (_roleDraftIsEmpty(draft)) {
      setState(() => _error = 'Please write at least a role name, mission, or prompt template before polishing.');
      return;
    }
    setState(() {
      _polishing = true;
      _error = null;
      _polishNote = null;
    });
    try {
      final result = await RepoKnowledgeDigestService().polishRole(draft);
      if (!mounted) return;
      _applyRole(result.role);
      setState(() {
        _polishing = false;
        _polishNote = result.usedProvider
            ? 'AI 已按 MobileCode Role 标准润色，保存前你仍可继续编辑。'
            : 'AI 不可用，已用本地模板标准化：${result.fallbackReason ?? 'fallback used.'}';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _polishing = false;
        _error = _compact(error.toString(), 160);
      });
    }
  }

  MobileCodeRole _draftRole() {
    return widget.role.copyWith(
      name: _name.text.trim(),
      summary: _summary.text.trim(),
      mission: _mission.text.trim(),
      personality: _personality.text.trim(),
      responsibilities: _splitLines(_responsibilities.text),
      guardrails: _splitLines(_guardrails.text),
      successCriteria: _splitLines(_successCriteria.text),
      promptTemplate: _promptTemplate.text.trim(),
      builtIn: false,
      enabled: true,
    );
  }

  bool _roleDraftIsEmpty(MobileCodeRole role) {
    return [
      role.name,
      role.summary,
      role.mission,
      role.personality,
      role.promptTemplate,
      ...role.responsibilities,
      ...role.guardrails,
      ...role.successCriteria,
    ].every((item) => item.trim().isEmpty);
  }

  void _applyRole(MobileCodeRole role) {
    _name.text = role.name;
    _summary.text = role.summary;
    _mission.text = role.mission;
    _personality.text = role.personality;
    _responsibilities.text = _joinLines(role.responsibilities);
    _guardrails.text = _joinLines(role.guardrails);
    _successCriteria.text = _joinLines(role.successCriteria);
    _promptTemplate.text = role.promptTemplate;
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Role name is required.');
      return;
    }
    final edited = widget.role.copyWith(
      name: name,
      summary: _summary.text.trim(),
      mission: _mission.text.trim(),
      personality: _personality.text.trim(),
      responsibilities: _splitLines(_responsibilities.text),
      guardrails: _splitLines(_guardrails.text),
      successCriteria: _splitLines(_successCriteria.text),
      promptTemplate: _promptTemplate.text.trim(),
      builtIn: false,
      enabled: true,
    );
    Navigator.of(context).pop(edited);
  }
}

class _MemoryRuleProposalEditSheet extends StatefulWidget {
  const _MemoryRuleProposalEditSheet({required this.rule});

  final MemoryRule rule;

  @override
  State<_MemoryRuleProposalEditSheet> createState() => _MemoryRuleProposalEditSheetState();
}

class _MemoryRuleProposalEditSheetState extends State<_MemoryRuleProposalEditSheet> {
  late final TextEditingController _title;
  late final TextEditingController _category;
  late final TextEditingController _rule;
  String? _error;
  String? _polishNote;
  bool _polishing = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.rule.title);
    _category = TextEditingController(text: widget.rule.category);
    _rule = TextEditingController(text: widget.rule.rule);
  }

  @override
  void dispose() {
    _title.dispose();
    _category.dispose();
    _rule.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.78,
      child: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(18, 14, 18, MediaQuery.of(context).viewInsets.bottom + 18),
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(color: _line, borderRadius: BorderRadius.circular(99)),
              ),
            ),
            const SizedBox(height: 14),
            const Text('Edit Memory rule before saving', style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 6),
            const Text(
              '只保存长期有价值的偏好、规范和工作流规则。保存后写入 App Memory，不改仓库文件。',
              style: TextStyle(color: _muted, height: 1.35),
            ),
            const SizedBox(height: 12),
            _PolishActionBox(
              title: 'AI 润色记忆规则',
              detail: '把粗略规则整理成长期可复用的 Memory；不会保存 prompt、response 或一次性任务内容。',
              note: _polishNote,
              polishing: _polishing,
              onPressed: _polish,
            ),
            const SizedBox(height: 14),
            _EditTextField(controller: _title, label: 'Title', icon: Icons.rule_outlined),
            _EditTextField(controller: _category, label: 'Category', icon: Icons.label_outline),
            _EditTextField(controller: _rule, label: 'Rule', icon: Icons.psychology_alt_outlined, maxLines: 6),
            if (widget.rule.evidenceRepos.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Evidence repos', style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 12)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final repo in widget.rule.evidenceRepos.take(5))
                    _HubPill(label: repo, icon: Icons.folder_outlined, color: _faint),
                ],
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: _rose, height: 1.3)),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _polishing ? null : _save,
                    icon: const Icon(Icons.library_add_check_outlined),
                    label: const Text('Save edited Memory'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _polish() async {
    final draft = widget.rule.copyWith(
      title: _title.text.trim(),
      category: _category.text.trim(),
      rule: _rule.text.trim(),
      enabled: true,
    );
    if (draft.title.trim().isEmpty && draft.rule.trim().isEmpty) {
      setState(() => _error = 'Please write a title or rule before polishing.');
      return;
    }
    setState(() {
      _polishing = true;
      _error = null;
      _polishNote = null;
    });
    try {
      final result = await RepoKnowledgeDigestService().polishMemoryRule(draft);
      if (!mounted) return;
      _title.text = result.rule.title;
      _category.text = result.rule.category;
      _rule.text = result.rule.rule;
      setState(() {
        _polishing = false;
        _polishNote = result.usedProvider
            ? 'AI 已整理为可长期复用的 Memory 规则。'
            : 'AI 不可用，已用本地模板标准化：${result.fallbackReason ?? 'fallback used.'}';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _polishing = false;
        _error = _compact(error.toString(), 160);
      });
    }
  }

  void _save() {
    final title = _title.text.trim();
    final rule = _rule.text.trim();
    if (title.isEmpty || rule.isEmpty) {
      setState(() => _error = 'Title and rule are required.');
      return;
    }
    Navigator.of(context).pop(widget.rule.copyWith(
          title: title,
          category: _category.text.trim().isEmpty ? 'repo-insight' : _category.text.trim(),
          rule: rule,
          enabled: true,
        ));
  }
}

class _PolishActionBox extends StatelessWidget {
  const _PolishActionBox({
    required this.title,
    required this.detail,
    required this.polishing,
    required this.onPressed,
    this.note,
  });

  final String title;
  final String detail;
  final String? note;
  final bool polishing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _violet.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _violet.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_fix_high_outlined, color: _violet, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 13),
                ),
              ),
              OutlinedButton.icon(
                onPressed: polishing ? null : onPressed,
                icon: polishing
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome_outlined, size: 16),
                label: Text(polishing ? '润色中...' : 'AI 润色'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(detail, style: const TextStyle(color: _muted, fontSize: 12, height: 1.35)),
          if (note != null) ...[
            const SizedBox(height: 8),
            Text(note!, style: const TextStyle(color: _violet, fontSize: 11.5, height: 1.3, fontWeight: FontWeight.w700)),
          ],
        ],
      ),
    );
  }
}

class _EditTextField extends StatelessWidget {
  const _EditTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.maxLines = 1,
    this.helperText,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final int maxLines;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        minLines: maxLines == 1 ? 1 : null,
        decoration: InputDecoration(
          labelText: label,
          helperText: helperText,
          prefixIcon: Icon(icon),
          alignLabelWithHint: maxLines > 1,
        ),
      ),
    );
  }
}

String _joinLines(List<String> values) => values.where((value) => value.trim().isNotEmpty).join('\n');

List<String> _splitLines(String value) {
  return value
      .split(RegExp(r'[\n;]+'))
      .map((line) => line.replaceFirst(RegExp(r'^[-*•\d.]+\s*'), '').trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
}

class _ReleaseAssetChip extends StatelessWidget {
  const _ReleaseAssetChip({
    required this.asset,
    required this.onTap,
  });

  final GitHubReleaseAsset asset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final size = asset.sizeBytes == null ? null : _bytesLabel(asset.sizeBytes!);
    final downloads = asset.downloadCount == null ? null : '${asset.downloadCount} dl';
    return ActionChip(
      avatar: const Icon(Icons.download_outlined, color: _blue, size: 16),
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: Text(
          [asset.name, if (size != null) size, if (downloads != null) downloads].join(' · '),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      side: BorderSide(color: _blue.withOpacity(0.25)),
      backgroundColor: _panel,
      labelStyle: const TextStyle(color: _text, fontSize: 11.5, fontWeight: FontWeight.w800),
      onPressed: onTap,
    );
  }
}

class _RepoWorkspaceSheet extends StatefulWidget {
  const _RepoWorkspaceSheet({
    required this.repo,
    required this.hub,
    required this.runtimeManager,
    required this.onMessage,
  });

  final GitHubRepo repo;
  final GitHubRepoHubService hub;
  final RuntimeManager runtimeManager;
  final void Function(String message, {bool isError}) onMessage;

  @override
  State<_RepoWorkspaceSheet> createState() => _RepoWorkspaceSheetState();
}

class _RepoWorkspaceSheetState extends State<_RepoWorkspaceSheet> {
  late Future<List<GitHubWorkspaceEntry>> _tree;
  late Future<GitHubRepoLocalState> _localState;
  late Future<List<GitHubRuntimeWorkspaceSyncRecord>> _recentSyncs;
  String _path = '';
  bool _openingFile = false;
  bool _syncingRuntime = false;
  String? _sharedCopyPath;

  @override
  void initState() {
    super.initState();
    _tree = widget.hub.loadRemoteTree(widget.repo);
    _localState = widget.hub.localStateFor(widget.repo);
    _recentSyncs = widget.hub.loadRuntimeWorkspaceSyncs(repo: widget.repo);
  }

  void _loadPath(String path) {
    setState(() {
      _path = path;
      _tree = widget.hub.loadRemoteTree(widget.repo, path: path);
    });
  }

  void _refreshLocalState() {
    setState(() {
      _localState = widget.hub.localStateFor(widget.repo);
      _recentSyncs = widget.hub.loadRuntimeWorkspaceSyncs(repo: widget.repo);
    });
  }

  void _goUp() {
    if (_path.isEmpty) return;
    final segments = _path.split('/')..removeLast();
    _loadPath(segments.join('/'));
  }

  Future<void> _openFile(GitHubWorkspaceEntry entry) async {
    if (_openingFile) return;
    setState(() => _openingFile = true);
    try {
      final file = await widget.hub.readRemoteFile(widget.repo, entry.path);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: _panel,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
        builder: (_) => _RemoteFileEditorSheet(
          repo: widget.repo,
          file: file,
          onReload: () => widget.hub.readRemoteFile(widget.repo, file.path),
          onCommit: (content, message, sha) async {
            await widget.hub.commitRemoteFile(
              widget.repo,
              path: file.path,
              content: content,
              message: message,
              sha: sha,
            );
            widget.onMessage('Committed ${file.path}.');
            _loadPath(_path);
          },
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      widget.onMessage(_compact(error.toString(), 160), isError: true);
    } finally {
      if (mounted) setState(() => _openingFile = false);
    }
  }

  Future<void> _copyRuntimePath(String path, String label) async {
    await Clipboard.setData(ClipboardData(text: path));
    if (!mounted) return;
    widget.onMessage('$label copied.');
  }

  Future<void> _copyTermuxCdCommand(GitHubRepoLocalState local) async {
    final command = 'cd ${_shellArg(local.path)} && ls';
    await Clipboard.setData(ClipboardData(text: command));
    if (!mounted) return;
    widget.onMessage('Termux cd command copied.');
  }

  Future<void> _syncRuntimeWorkspace(GitHubRepoLocalState local) async {
    if (_syncingRuntime) return;
    setState(() => _syncingRuntime = true);
    try {
      await widget.runtimeManager.initialize();
      final provider = widget.runtimeManager.activeProvider;
      if (provider is! TermuxDaemonProvider) {
        throw StateError('Active runtime is not a Termux daemon. Start the Termux helper daemon, then retry.');
      }
      final sourcePath = local.path.trim();
      final rawWorkspaceRoot = provider.workspaceRoot?.trim();
      final workspaceRoot = rawWorkspaceRoot?.replaceFirst(RegExp(r'/+$'), '');
      if (workspaceRoot != null &&
          workspaceRoot.isNotEmpty &&
          sourcePath != workspaceRoot &&
          !sourcePath.startsWith('$workspaceRoot/')) {
        throw StateError('Runtime workspace is outside the Termux daemon workspace root.');
      }

      final targetPath = _sharedRuntimeWorkspacePath(widget.repo);
      final mkdirResult = await widget.runtimeManager.execute(
        'mkdir -p ${_shellArg(targetPath)}',
        timeout: const Duration(seconds: 20),
      );
      if (!mkdirResult.success) throw StateError(_runtimeCommandFailureMessage(mkdirResult));

      final copyResult = await widget.runtimeManager.execute(
        'cp -R ${_shellArg('$sourcePath/.')} ${_shellArg(targetPath)}',
        timeout: const Duration(minutes: 3),
      );
      if (!copyResult.success) throw StateError(_runtimeCommandFailureMessage(copyResult));

      await widget.hub.ensureRuntimeGitWorkspace(widget.repo, runtimePath: sourcePath);
      await widget.hub.recordRuntimeWorkspaceSync(
        widget.repo,
        runtimePath: sourcePath,
        sharedPath: targetPath,
      );
      await Clipboard.setData(ClipboardData(text: targetPath));
      if (!mounted) return;
      setState(() {
        _sharedCopyPath = targetPath;
        _localState = widget.hub.localStateFor(widget.repo);
        _recentSyncs = widget.hub.loadRuntimeWorkspaceSyncs(repo: widget.repo);
      });
      widget.onMessage('Runtime workspace synced to shared folder. Path copied: $targetPath');
    } on Object catch (error) {
      if (!mounted) return;
      widget.onMessage(_friendlyRuntimeSyncError(error), isError: true);
    } finally {
      if (mounted) setState(() => _syncingRuntime = false);
    }
  }

  Future<void> _openSharedRuntimeFolder([String? folderPath]) async {
    final path = folderPath ?? _sharedCopyPath ?? _sharedRuntimeWorkspacePath(widget.repo);
    final opened = await launchUrl(Uri.file(path), mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (opened) {
      widget.onMessage('Opened shared runtime folder.');
    } else {
      await Clipboard.setData(ClipboardData(text: path));
      widget.onMessage('Could not open folder directly. Shared folder path copied.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
        child: FutureBuilder<GitHubRepoLocalState>(
          future: _localState,
          builder: (context, localSnapshot) {
            final local = localSnapshot.data;
            final runtimeLocal = local?.runtimeGit == true ? local : null;
            final listHeightFactor = runtimeLocal != null ? 0.48 : 0.66;
            return FutureBuilder<List<GitHubWorkspaceEntry>>(
              future: _tree,
              builder: (context, snapshot) {
                final entries = snapshot.data ?? const <GitHubWorkspaceEntry>[];
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.folder_copy_outlined, color: _blue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.repo.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: _text, fontSize: 17, fontWeight: FontWeight.w900),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Refresh workspace',
                          onPressed: () {
                            _refreshLocalState();
                            _loadPath(_path);
                          },
                          icon: const Icon(Icons.refresh_outlined),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _path.isEmpty ? 'API workspace · ${widget.repo.defaultBranch}' : _path,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _muted, fontSize: 12, height: 1.3),
                    ),
                    if (runtimeLocal != null) ...[
                      const SizedBox(height: 10),
                      FutureBuilder<List<GitHubRuntimeWorkspaceSyncRecord>>(
                        future: _recentSyncs,
                        builder: (context, syncSnapshot) {
                          return _RuntimeWorkspacePanel(
                            local: runtimeLocal,
                            sharedPath: _sharedCopyPath ?? _sharedRuntimeWorkspacePath(widget.repo),
                            recentSyncs: syncSnapshot.data ?? const <GitHubRuntimeWorkspaceSyncRecord>[],
                            syncing: _syncingRuntime,
                            onCopyRuntimePath: () => unawaited(_copyRuntimePath(runtimeLocal.path, 'Runtime path')),
                            onCopyCdCommand: () => unawaited(_copyTermuxCdCommand(runtimeLocal)),
                            onSyncToShared: () => unawaited(_syncRuntimeWorkspace(runtimeLocal)),
                            onOpenShared: () => unawaited(_openSharedRuntimeFolder()),
                            onCopySharedPath: () => unawaited(_copyRuntimePath(_sharedCopyPath ?? _sharedRuntimeWorkspacePath(widget.repo), 'Shared folder path')),
                            onOpenRecord: (record) => unawaited(_openSharedRuntimeFolder(record.sharedPath)),
                            onCopyRecord: (record) => unawaited(_copyRuntimePath(record.sharedPath, 'Recent shared folder path')),
                          );
                        },
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (_path.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: OutlinedButton.icon(
                          onPressed: _goUp,
                          icon: const Icon(Icons.arrow_upward_outlined, size: 16),
                          label: const Text('Parent folder'),
                        ),
                      ),
                    SizedBox(
                      height: MediaQuery.of(context).size.height * listHeightFactor,
                      child: snapshot.connectionState == ConnectionState.waiting
                          ? const SizedBox(height: 260, child: Center(child: CircularProgressIndicator()))
                          : snapshot.hasError
                              ? _HubPanel(
                                  borderColor: _rose,
                                  child: Text(_compact(snapshot.error.toString(), 180), style: const TextStyle(color: _rose, height: 1.35)),
                                )
                              : entries.isEmpty
                                  ? const _HubPanel(child: Text('No files in this folder.', style: TextStyle(color: _muted)))
                                  : ListView.separated(
                                      shrinkWrap: true,
                                      itemCount: entries.length,
                                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                                      itemBuilder: (context, index) {
                                        final entry = entries[index];
                                        return _HubPanel(
                                          child: InkWell(
                                            onTap: entry.isDirectory ? () => _loadPath(entry.path) : () => unawaited(_openFile(entry)),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  entry.isDirectory ? Icons.folder_outlined : Icons.description_outlined,
                                                  color: entry.isDirectory ? _amber : _blue,
                                                  size: 20,
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _text, fontWeight: FontWeight.w800)),
                                                      Text(
                                                        entry.isDirectory ? 'folder' : '${entry.size ?? 0} bytes',
                                                        style: const TextStyle(color: _faint, fontSize: 11),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                if (_openingFile && entry.isFile)
                                                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                                else
                                                  Icon(entry.isDirectory ? Icons.chevron_right : Icons.edit_outlined, color: _faint, size: 18),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _RuntimeWorkspacePanel extends StatelessWidget {
  const _RuntimeWorkspacePanel({
    required this.local,
    required this.sharedPath,
    required this.recentSyncs,
    required this.syncing,
    required this.onCopyRuntimePath,
    required this.onCopyCdCommand,
    required this.onSyncToShared,
    required this.onOpenShared,
    required this.onCopySharedPath,
    required this.onOpenRecord,
    required this.onCopyRecord,
  });

  final GitHubRepoLocalState local;
  final String sharedPath;
  final List<GitHubRuntimeWorkspaceSyncRecord> recentSyncs;
  final bool syncing;
  final VoidCallback onCopyRuntimePath;
  final VoidCallback onCopyCdCommand;
  final VoidCallback onSyncToShared;
  final VoidCallback onOpenShared;
  final VoidCallback onCopySharedPath;
  final ValueChanged<GitHubRuntimeWorkspaceSyncRecord> onOpenRecord;
  final ValueChanged<GitHubRuntimeWorkspaceSyncRecord> onCopyRecord;

  @override
  Widget build(BuildContext context) {
    return _HubPanel(
      borderColor: _mint.withOpacity(0.28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.sync_alt_outlined, color: _mint, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Runtime workspace',
                  style: TextStyle(color: _text, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            local.path,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _muted, fontSize: 11.5, height: 1.3),
          ),
          const SizedBox(height: 6),
          Text(
            'Termux clone lives in the runtime workspace. Sync a copy to $sharedPath when you want to browse it from the phone file manager.',
            style: const TextStyle(color: _faint, fontSize: 11.5, height: 1.35),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onCopyRuntimePath,
                icon: const Icon(Icons.copy_outlined, size: 16),
                label: const Text('复制 Runtime 路径'),
              ),
              OutlinedButton.icon(
                onPressed: onCopyCdCommand,
                icon: const Icon(Icons.terminal_outlined, size: 16),
                label: const Text('复制 cd 命令'),
              ),
              FilledButton.icon(
                onPressed: syncing ? null : onSyncToShared,
                icon: syncing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.sync_outlined, size: 16),
                label: Text(syncing ? '同步中...' : '同步到共享目录'),
              ),
              OutlinedButton.icon(
                onPressed: onOpenShared,
                icon: const Icon(Icons.folder_open_outlined, size: 16),
                label: const Text('打开共享目录'),
              ),
              OutlinedButton.icon(
                onPressed: onCopySharedPath,
                icon: const Icon(Icons.content_copy_outlined, size: 16),
                label: const Text('复制共享路径'),
              ),
            ],
          ),
          if (recentSyncs.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              '最近同步目录',
              style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 12),
            ),
            const SizedBox(height: 8),
            for (final record in recentSyncs.take(3)) ...[
              _RuntimeSyncRecordTile(
                record: record,
                onOpen: () => onOpenRecord(record),
                onCopy: () => onCopyRecord(record),
              ),
              const SizedBox(height: 7),
            ],
          ],
        ],
      ),
    );
  }
}

class _RuntimeSyncRecordTile extends StatelessWidget {
  const _RuntimeSyncRecordTile({
    required this.record,
    required this.onOpen,
    required this.onCopy,
  });

  final GitHubRuntimeWorkspaceSyncRecord record;
  final VoidCallback onOpen;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _mint.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _mint.withOpacity(0.16)),
      ),
      child: Row(
        children: [
          const Icon(Icons.history_outlined, color: _mint, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.sharedPath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _text, fontSize: 11.5, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_timeAgo(record.syncedAt)} · ${record.repoFullName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _faint, fontSize: 10.5),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Open shared folder',
            visualDensity: VisualDensity.compact,
            onPressed: onOpen,
            icon: const Icon(Icons.folder_open_outlined, color: _blue, size: 18),
          ),
          IconButton(
            tooltip: 'Copy shared path',
            visualDensity: VisualDensity.compact,
            onPressed: onCopy,
            icon: const Icon(Icons.copy_outlined, color: _blue, size: 18),
          ),
        ],
      ),
    );
  }
}

class _RemoteFileEditorSheet extends StatefulWidget {
  const _RemoteFileEditorSheet({
    required this.repo,
    required this.file,
    required this.onReload,
    required this.onCommit,
  });

  final GitHubRepo repo;
  final GitHubRemoteFile file;
  final Future<GitHubRemoteFile> Function() onReload;
  final Future<void> Function(String content, String message, String? sha) onCommit;

  @override
  State<_RemoteFileEditorSheet> createState() => _RemoteFileEditorSheetState();
}

class _RemoteFileEditorSheetState extends State<_RemoteFileEditorSheet> {
  late final TextEditingController _content;
  late final TextEditingController _message;
  late String _originalContent;
  String? _sha;
  bool _saving = false;
  bool _reloading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _content = TextEditingController(text: widget.file.content);
    _message = TextEditingController(text: 'Update ${widget.file.path} from MobileCode');
    _originalContent = widget.file.content;
    _sha = widget.file.sha;
  }

  @override
  void dispose() {
    _content.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _commit() async {
    final message = _message.text.trim();
    if (message.isEmpty) {
      setState(() => _error = 'Commit message is required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onCommit(_content.text, message, _sha);
      if (!mounted) return;
      Navigator.pop(context);
    } on GitHubDeepException catch (error) {
      if (!mounted) return;
      final lower = error.message.toLowerCase();
      final conflict = error.statusCode == 409 || error.statusCode == 422 || lower.contains('sha');
      setState(() {
        _saving = false;
        _error = conflict
            ? 'Remote file changed before this commit. Reload the latest version, review your edits, then commit again.'
            : _compact(error.toString(), 180);
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _compact(error.toString(), 180);
      });
    }
  }

  Future<void> _reloadRemote() async {
    setState(() {
      _reloading = true;
      _error = null;
    });
    try {
      final remote = await widget.onReload();
      if (!mounted) return;
      setState(() {
        _originalContent = remote.content;
        _sha = remote.sha;
        _content.text = remote.content;
        _reloading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _reloading = false;
        _error = _compact(error.toString(), 180);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final changed = _content.text != _originalContent;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 18 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.edit_document, color: _blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.file.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _text, fontSize: 16, fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _content,
                minLines: 12,
                maxLines: 18,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: const InputDecoration(labelText: 'Remote file content'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _message,
                enabled: !_saving,
                decoration: const InputDecoration(labelText: 'Commit message'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: _rose, fontSize: 12, height: 1.35)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _reloading ? null : () => unawaited(_reloadRemote()),
                  icon: _reloading
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh_outlined, size: 16),
                  label: Text(_reloading ? 'Reloading...' : 'Reload remote file'),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving || !changed ? null : () => unawaited(_commit()),
                  icon: _saving
                      ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.commit_outlined),
                  label: Text(_saving ? 'Committing...' : 'Commit through GitHub API'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RepoActionsSheet extends StatefulWidget {
  const _RepoActionsSheet({
    required this.repo,
    required this.hub,
    required this.onOpenUrl,
    required this.onMessage,
  });

  final GitHubRepo repo;
  final GitHubRepoHubService hub;
  final Future<void> Function(String? url, String label) onOpenUrl;
  final void Function(String message, {bool isError}) onMessage;

  @override
  State<_RepoActionsSheet> createState() => _RepoActionsSheetState();
}

class _RepoActionsSheetState extends State<_RepoActionsSheet> {
  late Future<GitHubActionsSnapshot> _snapshot;
  late Future<List<GitHubArtifactDownloadRecord>> _downloads;
  bool _dispatching = false;
  int? _downloadingArtifactId;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _snapshot = widget.hub.loadActionsSnapshot(widget.repo);
    _downloads = widget.hub.loadArtifactDownloads(repo: widget.repo);
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted) return;
      setState(() => _snapshot = widget.hub.loadActionsSnapshot(widget.repo));
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _dispatch(String workflowId) async {
    setState(() => _dispatching = true);
    try {
      await widget.hub.dispatchWorkflow(widget.repo, workflowId);
      if (!mounted) return;
      widget.onMessage('Workflow dispatch requested.');
      setState(() => _snapshot = widget.hub.loadActionsSnapshot(widget.repo));
    } on Object catch (error) {
      if (!mounted) return;
      widget.onMessage(_compact(error.toString(), 150), isError: true);
    } finally {
      if (mounted) setState(() => _dispatching = false);
    }
  }

  Future<void> _downloadArtifact(Map<String, dynamic> artifact) async {
    final id = artifact['id'];
    if (id is! int) return;
    setState(() => _downloadingArtifactId = id);
    try {
      final path = await widget.hub.downloadArtifactZip(widget.repo, artifact);
      await Clipboard.setData(ClipboardData(text: path));
      final opened = await launchUrl(Uri.file(path), mode: LaunchMode.externalApplication);
      if (!mounted) return;
      setState(() => _downloads = widget.hub.loadArtifactDownloads(repo: widget.repo));
      widget.onMessage(opened ? 'Artifact downloaded and opened. Path copied.' : 'Artifact downloaded. Path copied.');
    } on Object catch (error) {
      if (!mounted) return;
      widget.onMessage(_compact(error.toString(), 160), isError: true);
    } finally {
      if (mounted) setState(() => _downloadingArtifactId = null);
    }
  }

  Future<void> _openDownloadedPath(String path) async {
    final opened = await launchUrl(Uri.file(path), mode: LaunchMode.externalApplication);
    if (!mounted) return;
    widget.onMessage(opened ? 'Opened downloaded artifact.' : 'Could not open artifact. Path copied.', isError: !opened);
    if (!opened) await Clipboard.setData(ClipboardData(text: path));
  }

  Future<void> _openDownloadFolder(String path) async {
    final folderPath = p.dirname(path);
    final opened = await launchUrl(Uri.file(folderPath), mode: LaunchMode.externalApplication);
    if (!mounted) return;
    widget.onMessage(opened ? 'Opened artifact folder.' : 'Folder path copied.', isError: !opened);
    if (!opened) await Clipboard.setData(ClipboardData(text: folderPath));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
        child: FutureBuilder<GitHubActionsSnapshot>(
          future: _snapshot,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(height: 220, child: Center(child: CircularProgressIndicator()));
            }
            if (snapshot.hasError) {
              return _HubPanel(
                borderColor: _rose,
                child: Text(_compact(snapshot.error.toString(), 180), style: const TextStyle(color: _rose, height: 1.35)),
              );
            }
            final data = snapshot.requireData;
            final latest = data.latestRun;
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.play_circle_outline, color: _blue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(widget.repo.fullName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _text, fontSize: 17, fontWeight: FontWeight.w900)),
                      ),
                      IconButton(
                        tooltip: 'Refresh run status',
                        onPressed: () => setState(() => _snapshot = widget.hub.loadActionsSnapshot(widget.repo)),
                        icon: const Icon(Icons.refresh_outlined),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _HubPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Latest GitHub Actions run', style: TextStyle(color: _text, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 8),
                        if (latest == null)
                          const Text('No workflow runs found yet.', style: TextStyle(color: _muted))
                        else ...[
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _HubPill(label: latest['status']?.toString() ?? 'unknown', icon: Icons.sync_outlined, color: _blue),
                              _HubPill(label: latest['conclusion']?.toString() ?? 'no conclusion', icon: Icons.verified_outlined, color: _mint),
                              _HubPill(label: '${data.artifacts.length} artifacts', icon: Icons.inventory_2_outlined, color: _violet),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${latest['name'] ?? 'workflow'} · ${latest['head_branch'] ?? widget.repo.defaultBranch}',
                            style: const TextStyle(color: _muted, height: 1.3),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: () => unawaited(widget.onOpenUrl(latest['html_url']?.toString(), 'Actions run')),
                            icon: const Icon(Icons.open_in_new_outlined, size: 16),
                            label: const Text('Open run'),
                          ),
                          if (data.artifacts.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            const Text('Artifacts', style: TextStyle(color: _text, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 6),
                            for (final raw in data.artifacts.take(4))
                              if (raw is Map<String, dynamic>)
                                _ArtifactRow(
                                  artifact: raw,
                                  downloading: _downloadingArtifactId == raw['id'],
                                  onDownload: () => unawaited(_downloadArtifact(raw)),
                                ),
                          ],
                        ],
                      ],
                    ),
                  ),
                  if (data.jobs.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _HubPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Run jobs', style: TextStyle(color: _text, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 8),
                          for (final raw in data.jobs.take(4))
                            if (raw is Map<String, dynamic>) _JobRow(job: raw),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  FutureBuilder<List<GitHubArtifactDownloadRecord>>(
                    future: _downloads,
                    builder: (context, downloadsSnapshot) {
                      final downloads = downloadsSnapshot.data ?? const <GitHubArtifactDownloadRecord>[];
                      if (downloads.isEmpty) {
                        return const _HubPanel(
                          child: Text('Downloaded artifacts will appear here with open, folder, and copy actions.', style: TextStyle(color: _muted, height: 1.35)),
                        );
                      }
                      return _HubPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Recent downloads', style: TextStyle(color: _text, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 8),
                            for (final record in downloads.take(4))
                              _DownloadRecordRow(
                                record: record,
                                onOpen: () => unawaited(_openDownloadedPath(record.path)),
                                onOpenFolder: () => unawaited(_openDownloadFolder(record.path)),
                                onCopyPath: () async {
                                  await Clipboard.setData(ClipboardData(text: record.path));
                                  widget.onMessage('Artifact path copied.');
                                },
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text('Workflows', style: TextStyle(color: _text, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  if (data.workflows.isEmpty)
                    const Text('No workflows found. Add .github/workflows to build on GitHub.', style: TextStyle(color: _muted))
                  else
                    for (final raw in data.workflows)
                      if (raw is Map<String, dynamic>)
                        _WorkflowRow(
                          workflow: raw,
                          dispatching: _dispatching,
                          onOpen: () => unawaited(widget.onOpenUrl(raw['html_url']?.toString(), 'workflow')),
                          onRun: () => unawaited(_dispatch((raw['id'] ?? raw['path'] ?? raw['name']).toString())),
                        ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ArtifactRow extends StatelessWidget {
  const _ArtifactRow({
    required this.artifact,
    required this.downloading,
    required this.onDownload,
  });

  final Map<String, dynamic> artifact;
  final bool downloading;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final expired = artifact['expired'] == true;
    final size = artifact['size_in_bytes'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(expired ? Icons.inventory_2_outlined : Icons.archive_outlined, color: expired ? _faint : _violet, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              artifact['name']?.toString() ?? 'Artifact',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _muted, fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          if (size is int)
            Text(_bytesLabel(size), style: const TextStyle(color: _faint, fontSize: 11)),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Download artifact zip',
            onPressed: expired || downloading ? null : onDownload,
            icon: downloading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download_outlined, size: 18),
          ),
        ],
      ),
    );
  }
}

class _JobRow extends StatelessWidget {
  const _JobRow({required this.job});

  final Map<String, dynamic> job;

  @override
  Widget build(BuildContext context) {
    final steps = (job['steps'] as List<dynamic>?) ?? const [];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_tree_outlined, color: _blue, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  job['name']?.toString() ?? 'Job',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _text, fontWeight: FontWeight.w800),
                ),
              ),
              _HubPill(
                label: job['conclusion']?.toString() ?? job['status']?.toString() ?? 'unknown',
                icon: Icons.sync_outlined,
                color: _mint,
              ),
            ],
          ),
          if (steps.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final raw in steps.take(5))
              if (raw is Map<String, dynamic>)
                Padding(
                  padding: const EdgeInsets.only(left: 24, bottom: 3),
                  child: Text(
                    '${raw['status'] ?? 'queued'} · ${raw['name'] ?? 'step'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 11),
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

class _DownloadRecordRow extends StatelessWidget {
  const _DownloadRecordRow({
    required this.record,
    required this.onOpen,
    required this.onOpenFolder,
    required this.onCopyPath,
  });

  final GitHubArtifactDownloadRecord record;
  final VoidCallback onOpen;
  final VoidCallback onOpenFolder;
  final VoidCallback onCopyPath;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.archive_outlined, color: _violet, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.artifactName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _text, fontWeight: FontWeight.w800, fontSize: 12),
                ),
                Text(
                  '${_timeAgo(record.downloadedAt)} · ${record.sizeBytes == null ? record.path : '${_bytesLabel(record.sizeBytes!)} · ${record.path}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _faint, fontSize: 10),
                ),
              ],
            ),
          ),
          IconButton(tooltip: 'Open artifact', onPressed: onOpen, icon: const Icon(Icons.open_in_new_outlined, size: 18)),
          IconButton(tooltip: 'Open folder', onPressed: onOpenFolder, icon: const Icon(Icons.folder_open_outlined, size: 18)),
          IconButton(tooltip: 'Copy path', onPressed: onCopyPath, icon: const Icon(Icons.copy_outlined, size: 18)),
        ],
      ),
    );
  }
}

class _WorkflowRow extends StatelessWidget {
  const _WorkflowRow({
    required this.workflow,
    required this.dispatching,
    required this.onOpen,
    required this.onRun,
  });

  final Map<String, dynamic> workflow;
  final bool dispatching;
  final VoidCallback onOpen;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _HubPanel(
        child: Row(
          children: [
            const Icon(Icons.schema_outlined, color: _blue, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(workflow['name']?.toString() ?? 'Workflow', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _text, fontWeight: FontWeight.w800)),
                  Text(workflow['state']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 12)),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Open workflow',
              onPressed: onOpen,
              icon: const Icon(Icons.open_in_new_outlined, size: 18),
            ),
            IconButton(
              tooltip: 'Run workflow',
              onPressed: dispatching ? null : onRun,
              icon: dispatching
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_arrow_outlined, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final String value;
  final bool selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(value),
    );
  }
}

class _HubPanel extends StatelessWidget {
  const _HubPanel({
    required this.child,
    this.borderColor = _line,
  });

  final Widget child;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A2555FF),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _HubPill extends StatelessWidget {
  const _HubPill({
    required this.label,
    required this.icon,
    required this.color,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11)),
        ],
      ),
    );
    if (onTap == null) return pill;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: pill,
      ),
    );
  }
}

String _pagesUrlFor(GitHubRepo repo) {
  final homepage = repo.homepage?.trim();
  if (homepage != null && homepage.startsWith(RegExp(r'https?://'))) {
    return homepage;
  }
  final owner = repo.owner.toLowerCase();
  final repoName = repo.name.toLowerCase();
  if (repoName == '$owner.github.io') {
    return 'https://$owner.github.io/';
  }
  return 'https://$owner.github.io/${repo.name}/';
}

String _repoChatPrompt(GitHubRepoHubItem item) {
  final repo = item.repo;
  final local = item.localState;
  final pages = repo.hasPages ? _pagesUrlFor(repo) : 'No GitHub Pages detected';
  final workspace = local.exists ? local.path : 'No phone workspace created yet';
  final mode = local.hasGit
      ? 'Git clone workspace (.git exists)'
      : local.remoteLinked
          ? 'Remote-linked GitHub API workspace (not a git clone)'
          : local.exists
              ? 'Phone folder without GitHub marker'
              : 'Not on phone';
  return '''
我想围绕 GitHub 仓库 ${repo.fullName} 进行 MobileCode 对话。

仓库信息：
- Repo URL: ${repo.webUrl}
- Pages URL: $pages
- 默认分支: ${repo.defaultBranch}
- 主要语言: ${repo.language ?? 'unknown'}
- 手机工作区状态: $mode
- 手机本地路径: $workspace

请先基于这个仓库上下文回答。若需要修改文件：
- Remote-linked 模式优先通过 GitHub API 读取/提交文件。
- Git clone 模式才使用本机 git 命令。
- 若用户明确需要 git push，而当前不是 Git clone，引导先点“Git 克隆”按钮。
- Not on phone 时先建议创建手机工作区或使用 GitHub API。
'''.trim();
}

String _repoWorkspaceModeLabel(GitHubRepoLocalState local) {
  if (local.runtimeGit) return 'Termux git clone';
  if (local.hasGit) return 'Git clone';
  if (local.remoteLinked) return 'Remote-linked';
  if (local.exists) return 'Phone folder';
  return 'Not on phone';
}

String _sourceSearchLabel(String source) {
  return switch (source) {
    'skill' => 'Search GitHub skills',
    'mcp' => 'Search GitHub MCP',
    'release' => 'Search release repos',
    _ => 'Search any GitHub repo',
  };
}

String _sourceSearchHint(String source) {
  return switch (source) {
    'skill' => 'frontend design skill, codex skill, SKILL.md...',
    'mcp' => 'github mcp server, lark mcp, filesystem mcp...',
    'release' => 'flutter apk, android release, github pages...',
    _ => 'owner/repo keywords, topic, language, product name...',
  };
}

String _sourceScopeCopy(String source) {
  return switch (source) {
    'owner' => 'Owner repos is the managed lane: your own account is smoothest; org repos still need collaborator permissions.',
    'skill' => 'Skill search is a discovery lane. Load only after reviewing source, manifest, and trust signals.',
    'mcp' => 'MCP search is a discovery lane. Register connectors disabled first, then enable only after review.',
    'release' => 'Release search finds repos with downloadable builds; publishing or pushing still requires repo permission.',
    _ => 'Any repo search is discovery-first. Open, copy, chat, or link read-only; push requires fork or write access.',
  };
}

String _timeAgo(DateTime value) {
  final diff = DateTime.now().difference(value);
  if (diff.inDays >= 365) return '${(diff.inDays / 365).floor()}y ago';
  if (diff.inDays >= 30) return '${(diff.inDays / 30).floor()}mo ago';
  if (diff.inDays >= 1) return '${diff.inDays}d ago';
  if (diff.inHours >= 1) return '${diff.inHours}h ago';
  if (diff.inMinutes >= 1) return '${diff.inMinutes}m ago';
  return 'just now';
}

String _cloneFailureMessage(RuntimeCommandResult result) {
  final output = [result.stderr, result.stdout]
      .where((part) => part.trim().isNotEmpty)
      .join(' ');
  if (output.trim().isEmpty) {
    return 'Clone failed with exit code ${result.exitCode}.';
  }
  return 'Clone failed: ${_compact(output, 180)}';
}

String _runtimeCommandFailureMessage(RuntimeCommandResult result) {
  final output = [result.stderr, result.stdout]
      .where((part) => part.trim().isNotEmpty)
      .join(' ');
  if (output.trim().isEmpty) {
    return 'Runtime command failed with exit code ${result.exitCode}.';
  }
  return _compact(output, 220);
}

String _friendlyCloneError(Object error) {
  final message = error.toString().replaceFirst(RegExp(r'^Bad state:\s*'), '').trim();
  final lower = message.toLowerCase();
  if (message.contains('Phone workspace already contains files but no .git folder')) {
    return '这个手机工作区已有非 Git 文件。请继续使用 Remote-linked/API 提交，或先清理该文件夹后再 Git 克隆。';
  }
  if (message.contains('does not expose git')) {
    return '当前 runtime 没有 git。可继续使用 Remote-linked/API 工作区，或安装 Helper/Termux git 后再克隆。';
  }
  if (lower.contains('authentication failed') || lower.contains('could not read username')) {
    return 'Git 克隆需要有效的 GitHub 凭据。公开仓库可先创建 Remote-linked 工作区；私有仓库请检查 token/权限。';
  }
  return _compact(message.isEmpty ? error.toString() : message, 180);
}

String _friendlyRuntimeSyncError(Object error) {
  final message = error.toString().replaceFirst(RegExp(r'^Bad state:\s*'), '').trim();
  final lower = message.toLowerCase();
  if (lower.contains('permission denied') && (lower.contains('/sdcard') || lower.contains('/storage'))) {
    return 'Termux 还没有共享存储权限。请在 Termux 运行 termux-setup-storage 后重试同步到共享目录。';
  }
  if (lower.contains('not a termux daemon')) {
    return '当前运行时不是 Termux daemon。请启动 Termux 里的 mobilecode helper daemon 后重试。';
  }
  if (lower.contains('outside the termux daemon workspace root')) {
    return 'Runtime workspace 路径不在 Termux daemon 工作区内，已阻止同步。请重新创建或刷新该仓库工作区。';
  }
  return _compact(message.isEmpty ? error.toString() : message, 220);
}

String _sharedRuntimeWorkspacePath(GitHubRepo repo) {
  return p.posix.join(
    '/sdcard/MobileCode/github',
    _safeRuntimePathSegment(repo.owner),
    _safeRuntimePathSegment(repo.name),
  );
}

String _safeRuntimePathSegment(String value) {
  final normalized = value.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-');
  final trimmed = normalized.replaceAll(RegExp(r'^-+|-+$'), '');
  return trimmed.isEmpty ? 'repo' : trimmed;
}

String _shellArg(String value) {
  final escaped = value.replaceAll("'", "'\"'\"'");
  return "'$escaped'";
}

String _compact(String value, int limit) {
  final singleLine = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (singleLine.length <= limit) return singleLine;
  return '${singleLine.substring(0, limit - 1)}…';
}

String _bytesLabel(int bytes) {
  if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '$bytes B';
}
