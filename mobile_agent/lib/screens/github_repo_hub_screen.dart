import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../models/github_repo.dart';
import '../services/github_deep_service.dart';
import '../services/github_repo_hub_service.dart';
import 'github_screen.dart';

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

class GitHubRepoHubScreen extends StatefulWidget {
  const GitHubRepoHubScreen({super.key});

  @override
  State<GitHubRepoHubScreen> createState() => _GitHubRepoHubScreenState();
}

class _GitHubRepoHubScreenState extends State<GitHubRepoHubScreen> {
  late final GitHubDeepService _github;
  late final GitHubRepoHubService _hub;
  final _ownerController = TextEditingController();
  final _searchController = TextEditingController();

  bool _loading = true;
  bool _authenticated = false;
  String? _error;
  String _filter = 'all';
  String _languageFilter = 'all';
  String _sort = 'pushed';
  List<GitHubRepoHubItem> _items = const [];

  @override
  void initState() {
    super.initState();
    _github = GitHubDeepService();
    _hub = GitHubRepoHubService(_github);
    _searchController.addListener(() => setState(() {}));
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _ownerController.dispose();
    _searchController.dispose();
    _github.dispose();
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
    });
    try {
      await _hub.initialize();
      if (!_hub.isAuthenticated) {
        if (!mounted) return;
        setState(() {
          _authenticated = false;
          _loading = false;
          _items = const [];
        });
        return;
      }
      final items = await _hub.loadHubItems(
        owner: _ownerController.text,
        sort: _sort,
      );
      if (!mounted) return;
      final keepLanguageFilter = _languageFilter == 'all' ||
          items.any((item) => (item.repo.language ?? '').toLowerCase() == _languageFilter);
      setState(() {
        _authenticated = true;
        _items = items;
        if (!keepLanguageFilter) _languageFilter = 'all';
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _compact(error.toString(), 180);
      });
    }
  }

  Future<void> _openLogin() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const GitHubScreen()));
    if (!mounted) return;
    await _refresh();
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

  Future<void> _openUrl(String? url, String label) async {
    if (url == null || url.isEmpty) return;
    final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!mounted) return;
    _toast(opened ? 'Opened $label.' : 'Could not open $label.', isError: !opened);
  }

  Future<void> _copy(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    _toast('$label copied.');
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
          if (!_authenticated && !_loading)
            _AuthPanel(onLogin: _openLogin)
          else ...[
            _HubPanel(
              child: Column(
                children: [
                  TextField(
                    controller: _ownerController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => unawaited(_refresh()),
                    decoration: InputDecoration(
                      labelText: 'GitHub user / org',
                      hintText: _hub.currentUser == null ? 'Leave blank for current login' : 'Blank = ${_hub.currentUser}',
                      prefixIcon: const Icon(Icons.account_circle_outlined),
                      suffixIcon: IconButton(
                        tooltip: 'Load repos',
                        onPressed: _loading ? null : _refresh,
                        icon: const Icon(Icons.travel_explore_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText: 'Search watched repos',
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
              const _HubPanel(
                child: Text('No repositories match this filter yet.', style: TextStyle(color: _muted)),
              )
            else
              for (final item in visible) ...[
                _RepoHubCard(
                  item: item,
                  onWatched: (value) => unawaited(_setWatched(item, value)),
                  onLinkWorkspace: () => unawaited(_linkWorkspace(item)),
                  onOpenRepo: () => unawaited(_openUrl(item.repo.webUrl, 'repository')),
                  onCopyPath: () => unawaited(_copy(item.localState.path, 'Workspace path')),
                  onActions: () => _showActions(item.repo),
                  onWorkspace: () => _showWorkspace(item.repo),
                ),
                const SizedBox(height: 10),
              ],
          ],
        ],
      ),
    );
  }

  void _setFilter(String value) {
    setState(() => _filter = value);
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
          const Text('GitHub login required', style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 6),
          const Text(
            'Sign in once to list repos, create a watchlist, publish Pages, and later trigger GitHub Actions builds from the phone.',
            style: TextStyle(color: _muted, height: 1.35),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onLogin,
            icon: const Icon(Icons.login_outlined),
            label: const Text('Open GitHub login'),
          ),
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

class _RepoHubCard extends StatelessWidget {
  const _RepoHubCard({
    required this.item,
    required this.onWatched,
    required this.onLinkWorkspace,
    required this.onOpenRepo,
    required this.onCopyPath,
    required this.onActions,
    required this.onWorkspace,
  });

  final GitHubRepoHubItem item;
  final ValueChanged<bool> onWatched;
  final VoidCallback onLinkWorkspace;
  final VoidCallback onOpenRepo;
  final VoidCallback onCopyPath;
  final VoidCallback onActions;
  final VoidCallback onWorkspace;

  @override
  Widget build(BuildContext context) {
    final repo = item.repo;
    final local = item.localState;
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
              if (repo.hasPages) const _HubPill(label: 'Pages', icon: Icons.web_outlined, color: _mint),
              _HubPill(label: local.statusLabel, icon: local.hasGit ? Icons.call_split_outlined : Icons.folder_open_outlined, color: localColor),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            'Pushed ${_timeAgo(repo.pushedAt)} · ${local.path}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _faint, fontSize: 11, height: 1.3),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onLinkWorkspace,
                icon: const Icon(Icons.add_to_drive_outlined, size: 16),
                label: Text(local.exists ? '刷新本机链接' : '加入手机工作区'),
              ),
              OutlinedButton.icon(
                onPressed: onActions,
                icon: const Icon(Icons.play_circle_outline, size: 16),
                label: const Text('Actions'),
              ),
              OutlinedButton.icon(
                onPressed: onWorkspace,
                icon: const Icon(Icons.folder_copy_outlined, size: 16),
                label: const Text('Files'),
              ),
              OutlinedButton.icon(
                onPressed: onOpenRepo,
                icon: const Icon(Icons.open_in_new_outlined, size: 16),
                label: const Text('仓库'),
              ),
              OutlinedButton.icon(
                onPressed: onCopyPath,
                icon: const Icon(Icons.copy_outlined, size: 16),
                label: const Text('路径'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RepoWorkspaceSheet extends StatefulWidget {
  const _RepoWorkspaceSheet({
    required this.repo,
    required this.hub,
    required this.onMessage,
  });

  final GitHubRepo repo;
  final GitHubRepoHubService hub;
  final void Function(String message, {bool isError}) onMessage;

  @override
  State<_RepoWorkspaceSheet> createState() => _RepoWorkspaceSheetState();
}

class _RepoWorkspaceSheetState extends State<_RepoWorkspaceSheet> {
  late Future<List<GitHubWorkspaceEntry>> _tree;
  String _path = '';
  bool _openingFile = false;

  @override
  void initState() {
    super.initState();
    _tree = widget.hub.loadRemoteTree(widget.repo);
  }

  void _loadPath(String path) {
    setState(() {
      _path = path;
      _tree = widget.hub.loadRemoteTree(widget.repo, path: path);
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

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
        child: FutureBuilder<List<GitHubWorkspaceEntry>>(
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
                      tooltip: 'Refresh files',
                      onPressed: () => _loadPath(_path),
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
                  height: MediaQuery.of(context).size.height * 0.66,
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
        ),
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
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
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
  }
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
