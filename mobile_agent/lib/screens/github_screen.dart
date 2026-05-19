import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme.dart';
import '../models/github_repo.dart';
import '../services/github_deep_service.dart';
import '../services/repo_intent_polish_service.dart';
import '../widgets/glass_card_widget.dart';
import 'github_repo_screen.dart';
import 'github_issue_detail_screen.dart';
import 'github_pr_review_screen.dart';

// ═════════════════════════════════════════════════════════════════════════════
// GITHUB SCREEN — Deep Integration Hub (Enhanced UX)
// ═════════════════════════════════════════════════════════════════════════════
class GitHubScreen extends StatefulWidget {
  const GitHubScreen({super.key});

  @override
  State<GitHubScreen> createState() => _GitHubScreenState();
}

class _GitHubScreenState extends State<GitHubScreen>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  static const _systemTools = MethodChannel('mobilecode/system_tools');
  static const _oauthClientId = String.fromEnvironment('MOBILECODE_GITHUB_OAUTH_CLIENT_ID');
  static const _oauthClientSecret = String.fromEnvironment('MOBILECODE_GITHUB_OAUTH_CLIENT_SECRET');
  static const _oauthRedirectUri = String.fromEnvironment(
    'MOBILECODE_GITHUB_OAUTH_REDIRECT_URI',
    defaultValue: 'mobilecode://github/oauth',
  );
  static const _oauthScopes = 'repo user notifications workflow';

  late TabController _tabCtrl;
  final GitHubDeepService _svc = GitHubDeepService();
  final _tokenCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  bool _auth = false;
  String? _error;
  int _unreadCount = 0;

  // Data caches per tab
  List<GitHubRepo> _repos = [];
  List<dynamic> _issues = [];
  List<dynamic> _prs = [];
  List<dynamic> _notifications = [];
  List<dynamic> _searchResults = [];

  // Filters & Sorting
  String _repoFilter = 'all';
  String _repoSort = 'pushed';
  String? _repoLanguageFilter;
  String _issueFilter = 'open';
  String? _issueLabelFilter;
  String? _issueAssigneeFilter;
  int? _issueMilestoneFilter;
  String _prFilter = 'open';

  // UI state
  bool _searching = false;
  bool _showSearchInRepos = false;
  bool _oauthBusy = false;
  String? _oauthState;

  // Issue/PR dynamic filters
  List<dynamic> _repoLabels = [];
  List<dynamic> _repoMilestones = [];
  List<dynamic> _repoAssignees = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabCtrl = TabController(length: 4, vsync: this);
    _tabCtrl.addListener(_onTab);
    _init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_handlePendingOAuthCallback().then((_) => _refreshAuthState()));
    }
  }

  Future<void> _refreshAuthState() async {
    try {
      await _svc.initialize();
      await _handlePendingOAuthCallback();
      if (!mounted) return;
      if (_svc.isAuthenticated) {
        await _loadRepos();
      }
      if (!mounted) return;
      setState(() {
        _auth = _svc.isAuthenticated;
        _loading = false;
        if (_auth) _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _init() async {
    setState(() => _loading = true);
    try {
      await _svc.initialize();
      if (_svc.isAuthenticated) await _loadRepos();
      setState(() {
        _auth = _svc.isAuthenticated;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _onTab() {
    if (!_tabCtrl.indexIsChanging) {
      final i = _tabCtrl.index;
      if (_auth) {
        if (i == 0) _loadRepos();
        if (i == 1 && _issues.isEmpty) _loadIssues();
        if (i == 2 && _prs.isEmpty) _loadPRs();
        if (i == 3) _loadNotifications();
      }
    }
  }

  // ── Data Loading ───────────────────────────────────────────────────────────

  Future<void> _loadRepos() async {
    try {
      final r = await _svc.getRepos(
        type: _repoFilter == 'all' ? 'all' : _repoFilter,
        sort: _repoSort,
      );
      setState(() => _repos = r);
    } catch (e) {
      _toast('Failed to load repos: \$e', isError: true);
    }
  }

  Future<void> _loadIssues() async {
    if (_repos.isEmpty) return;
    try {
      // Load dynamic filters if empty
      if (_repoLabels.isEmpty) _loadIssueFilters();

      final list = await _svc.getIssues(
        _repos.first.owner,
        _repos.first.name,
        state: _issueFilter,
        labels: _issueLabelFilter,
        assignee: _issueAssigneeFilter,
      );
      setState(() => _issues = list);
    } catch (e) {
      _toast('Failed to load issues: \$e', isError: true);
    }
  }

  Future<void> _loadIssueFilters() async {
    if (_repos.isEmpty) return;
    try {
      final labels = await _svc.getLabels(_repos.first.owner, _repos.first.name);
      final milestones =
          await _svc.getMilestones(_repos.first.owner, _repos.first.name);
      setState(() {
        _repoLabels = labels;
        _repoMilestones = milestones;
      });
    } catch (_) {
      // Silently fail - filters are optional
    }
  }

  Future<void> _loadPRs() async {
    if (_repos.isEmpty) return;
    try {
      final list = await _svc.getPullRequests(
        _repos.first.owner,
        _repos.first.name,
        state: _prFilter,
      );
      setState(() => _prs = list);
    } catch (e) {
      _toast('Failed to load PRs: \$e', isError: true);
    }
  }

  Future<void> _loadNotifications() async {
    try {
      final n = await _svc.getNotifications(all: false);
      final count = await _svc.getUnreadNotificationCount();
      setState(() {
        _notifications = n;
        _unreadCount = count;
      });
    } catch (e) {
      _toast('Failed to load notifications: \$e', isError: true);
    }
  }

  // ── Auth ───────────────────────────────────────────────────────────────────

  Future<void> _authenticate() async {
    final token = _tokenCtrl.text.trim();
    if (token.isEmpty) return;
    setState(() => _loading = true);
    try {
      final ok = await _svc.authenticate(token);
      if (ok) {
        _tokenCtrl.clear();
        await _loadRepos();
        setState(() {
          _auth = true;
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Invalid token. Please check and try again.';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Auth failed: \$e';
        _loading = false;
      });
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove GitHub access?', style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text(
          'This removes the active token from this device. Public search still works, but private repos and write actions will require adding access again.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.logout, size: 16),
            label: const Text('Remove access'),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _svc.logout();
    setState(() {
      _auth = false;
      _repos.clear();
      _issues.clear();
      _prs.clear();
      _notifications.clear();
      _unreadCount = 0;
      _repoLabels.clear();
      _repoMilestones.clear();
    });
  }

  String _newOAuthState() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  Future<void> _launchOAuth() async {
    const tokenSetupUrl =
        'https://github.com/settings/tokens/new?description=MobileCode&scopes=repo,user,notifications,workflow';
    final state = _newOAuthState();
    _oauthState = state;
    final url = _oauthClientId.isEmpty
        ? tokenSetupUrl
        : Uri.https('github.com', '/login/oauth/authorize', {
            'client_id': _oauthClientId,
            'redirect_uri': _oauthRedirectUri,
            'scope': _oauthScopes,
            'state': state,
          }).toString();
    if (_oauthClientId.isEmpty) {
      setState(() {
        _error = 'This APK has no GitHub OAuth client configured yet. Create a token in the browser, then paste it above.';
      });
    }
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      _toast('Could not open GitHub: $e', isError: true);
    }
  }

  Future<void> _handlePendingOAuthCallback() async {
    if (_oauthBusy) return;
    String? rawLink;
    try {
      rawLink = await _systemTools.invokeMethod<String>('consumeInitialDeepLink');
    } catch (_) {
      return;
    }
    if (rawLink == null || rawLink.trim().isEmpty) return;
    final uri = Uri.tryParse(rawLink);
    if (uri == null || uri.scheme != 'mobilecode' || uri.host != 'github') return;
    final error = uri.queryParameters['error'];
    if (error != null && error.isNotEmpty) {
      final description = uri.queryParameters['error_description'] ?? error;
      if (mounted) setState(() => _error = 'GitHub OAuth failed: $description');
      return;
    }
    final code = uri.queryParameters['code'];
    if (code == null || code.isEmpty) return;
    final state = uri.queryParameters['state'];
    if (_oauthState != null && state != _oauthState) {
      if (mounted) setState(() => _error = 'GitHub OAuth state mismatch. Please try login again.');
      return;
    }
    if (_oauthClientId.isEmpty) {
      if (mounted) setState(() => _error = 'GitHub OAuth client id is missing. Paste a token or build with MOBILECODE_GITHUB_OAUTH_CLIENT_ID.');
      return;
    }
    if (mounted) {
      setState(() {
        _oauthBusy = true;
        _loading = true;
        _error = null;
      });
    }
    try {
      final ok = await _svc.authenticateWithOAuthCode(
        code: code,
        clientId: _oauthClientId,
        clientSecret: _oauthClientSecret,
        redirectUri: _oauthRedirectUri,
      );
      if (!mounted) return;
      if (ok) {
        await _loadRepos();
        setState(() {
          _auth = true;
          _loading = false;
          _oauthBusy = false;
          _oauthState = null;
        });
        _toast('GitHub OAuth login connected');
      } else {
        setState(() {
          _loading = false;
          _oauthBusy = false;
          _error = 'GitHub OAuth token was received but could not read /user.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _oauthBusy = false;
        _error = 'GitHub OAuth exchange failed: $e';
      });
    }
  }

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() => _searching = true);
    try {
      final r = await _svc.searchRepositories(q,
          language: _repoLanguageFilter);
      setState(() {
        _searchResults = r;
        _searching = false;
      });
    } catch (e) {
      setState(() => _searching = false);
      _toast('Search failed: \$e', isError: true);
    }
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _forkRepo(GitHubRepo repo) async {
    try {
      await _svc.forkRepo(repo.owner, repo.name);
      _toast('Forking \${repo.name}...');
      await _loadRepos();
    } catch (e) {
      _toast('Fork failed: \$e', isError: true);
    }
  }

  Future<void> _starRepo(GitHubRepo repo) async {
    try {
      final starred = await _svc.isStarred(repo.owner, repo.name);
      if (starred) {
        await _svc.unstarRepo(repo.owner, repo.name);
        _toast('Unstarred \${repo.name}');
      } else {
        await _svc.starRepo(repo.owner, repo.name);
        _toast('Starred \${repo.name}');
      }
    } catch (e) {
      _toast('Failed: \$e', isError: true);
    }
  }

  Future<void> _submitReview(dynamic pr, String event) async {
    if (_repos.isEmpty) return;
    try {
      await _svc.submitPullRequestReview(
          _repos.first.owner, _repos.first.name, pr['number'] as int,
          event: event);
      _toast('Review submitted: \$event');
    } catch (e) {
      _toast('Review failed: \$e', isError: true);
    }
  }

  // ── Toasts ─────────────────────────────────────────────────────────────────

  void _toast(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:
          Text(msg, style: const TextStyle(color: AppTheme.textPrimary)),
      backgroundColor:
          (isError ? AppTheme.error : AppTheme.success).withOpacity(0.9),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 3),
    ));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabCtrl.dispose();
    _tokenCtrl.dispose();
    _searchCtrl.dispose();
    _svc.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
          child: _loading
              ? _buildLoading()
              : !_auth
                  ? _buildAuth()
                  : _buildMain()),
      floatingActionButton: _auth ? _buildFAB() : null,
    );
  }

  // ── FAB ────────────────────────────────────────────────────────────────────

  Widget? _buildFAB() {
    VoidCallback? onPressed;
    String tooltip;
    IconData icon;

    switch (_tabCtrl.index) {
      case 0:
        onPressed = _showCreateRepoSheet;
        tooltip = 'Create Repository';
        icon = Icons.create_new_folder;
      case 1:
        onPressed = _createIssueSheet;
        tooltip = 'Create Issue';
        icon = Icons.add_comment;
      case 2:
        onPressed = _createPRSheet;
        tooltip = 'Create Pull Request';
        icon = Icons.call_merge;
      case 3:
        onPressed = _markAllNotificationsRead;
        tooltip = 'Mark All Read';
        icon = Icons.done_all;
      default:
        return null;
    }

    return FloatingActionButton.extended(
      onPressed: onPressed,
      backgroundColor: AppTheme.primary,
      icon: Icon(icon, size: 20, color: Colors.white),
      label: Text(
        tooltip,
        style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
      ),
    );
  }

  Future<void> _markAllNotificationsRead() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Mark All as Read?',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text(
            'This will mark all notifications as read. This action cannot be undone.',
            style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            child: const Text('Mark All Read'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await _svc.markAllNotificationsRead();
        await _loadNotifications();
        _toast('All notifications marked as read');
      } catch (e) {
        _toast('Failed: \$e', isError: true);
      }
    }
  }

  // ── Loading ────────────────────────────────────────────────────────────────

  Widget _buildLoading() => Center(
        child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(
                          AppTheme.primary.withOpacity(0.8)))),
              const SizedBox(height: 20),
              Text('Connecting to GitHub...',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textSecondary)),
            ]),
      );

  // ── Auth Screen ────────────────────────────────────────────────────────────

  Widget _buildAuth() => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 40),
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: AppTheme.accentGradient,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                        color: AppTheme.accent.withOpacity(0.3),
                        blurRadius: 20,
                        spreadRadius: 4)
                  ],
                ),
                child: const Icon(Icons.code, size: 40, color: Colors.white),
              ),
              const SizedBox(height: 24),
              Text('Connect to GitHub',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                  'Access your repositories, issues, pull requests,\nand notifications in one place.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textSecondary)),
              const SizedBox(height: 40),
              // PAT Card
              GlassCardWidget(
                  padding: const EdgeInsets.all(20),
                  borderRadius: 16,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Personal Access Token',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                    color: AppTheme.textPrimary,
                                    fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Text(
                            'Generate a token at github.com/settings/tokens with repo, user, and notifications scopes.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppTheme.textTertiary)),
                        const SizedBox(height: 16),
                        TextField(
                            controller: _tokenCtrl,
                            obscureText: true,
                            style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontFamily: AppTheme.fontCode),
                            decoration: _inputDecoration(
                                'ghp_xxxxxxxxxxxxxxxxxxxx',
                                icon: Icons.vpn_key)),
                        const SizedBox(height: 16),
                        SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _authenticate,
                              icon: const Icon(Icons.login, size: 18),
                              label: const Text('Connect with Token'),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primary,
                                  foregroundColor: AppTheme.textOnPrimary,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10))),
                            )),
                      ])),
              const SizedBox(height: 20),
              // OAuth is enabled only when the release build provides a GitHub OAuth client id.
              GlassCardWidget(
                  padding: const EdgeInsets.all(20),
                  borderRadius: 16,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_oauthClientId.isEmpty ? 'Browser token setup' : 'OAuth Web Login',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                    color: AppTheme.textPrimary,
                                    fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Text(
                            _oauthClientId.isEmpty
                                ? 'Open GitHub in the browser, create a token, then return and paste it above.'
                                : 'Sign in through GitHub, then MobileCode will exchange the callback code for a stored token.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppTheme.textTertiary)),
                        const SizedBox(height: 16),
                        SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _oauthBusy ? null : _launchOAuth,
                              icon: _oauthBusy
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.open_in_browser, size: 18),
                              label: Text(_oauthClientId.isEmpty ? 'Open GitHub token page' : 'Login with GitHub OAuth'),
                              style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.accent,
                                  side: const BorderSide(color: AppTheme.accent),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10))),
                            )),
                      ])),
              if (_error != null) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: AppTheme.error.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppTheme.error.withOpacity(0.3))),
                  child: Row(children: [
                    const Icon(Icons.error_outline,
                        color: AppTheme.error, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(_error!,
                            style: const TextStyle(
                                color: AppTheme.error, fontSize: 13))),
                  ]),
                ),
              ],
            ]),
      );

  // ── Main Screen with Tabs ──────────────────────────────────────────────────

  Widget _buildMain() => Column(children: [
        _buildHeader(),
        Container(
            color: AppTheme.backgroundElevated,
            child: TabBar(
              controller: _tabCtrl,
              labelColor: AppTheme.primary,
              unselectedLabelColor: AppTheme.textTertiary,
              indicatorColor: AppTheme.primary,
              indicatorWeight: 2.5,
              labelStyle: const TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
              unselectedLabelStyle: const TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 13,
                  fontWeight: FontWeight.w500),
              tabs: [
                const Tab(
                    icon: Icon(Icons.folder_outlined, size: 20), text: 'Repos'),
                const Tab(
                    icon: Icon(Icons.error_outline, size: 20), text: 'Issues'),
                const Tab(
                    icon: Icon(Icons.call_merge, size: 20), text: 'Pull Req'),
                Tab(
                    icon: Stack(clipBehavior: Clip.none, children: [
                      const Icon(Icons.notifications_outlined, size: 20),
                      if (_unreadCount > 0)
                        Positioned(
                            right: -6,
                            top: -4,
                            child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                    color: AppTheme.error,
                                    shape: BoxShape.circle),
                                constraints: const BoxConstraints(
                                    minWidth: 14, minHeight: 14),
                                child: Text(
                                    _unreadCount > 99
                                        ? '99+'
                                        : '\$_unreadCount',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold),
                                    textAlign: TextAlign.center))),
                    ]),
                    text: 'Alerts'),
              ],
            )),
        Expanded(
            child: TabBarView(controller: _tabCtrl, children: [
          _buildReposTab(),
          _buildIssuesTab(),
          _buildPRsTab(),
          _buildNotificationsTab(),
        ])),
      ]);

  // ── Header with Multi-Account Switcher ─────────────────────────────────────

  Widget _buildHeader() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
            color: AppTheme.backgroundElevated,
            border: Border(bottom: BorderSide(color: AppTheme.divider))),
        child: Row(children: [
          // Account switcher avatar
          _buildAccountSwitcher(),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(_svc.currentUser ?? 'GitHub User',
                    style: const TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary),
                    overflow: TextOverflow.ellipsis),
                Text('${_repos.length} repositories',
                    style: const TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 11,
                        color: AppTheme.textTertiary)),
              ])),
          IconButton(
              onPressed: _showSearchSheet,
              icon: const Icon(Icons.search,
                  size: 20, color: AppTheme.textSecondary)),
          IconButton(
              onPressed: () {
                final i = _tabCtrl.index;
                if (i == 0) _loadRepos();
                if (i == 1) _loadIssues();
                if (i == 2) _loadPRs();
                if (i == 3) _loadNotifications();
              },
              icon: const Icon(Icons.refresh,
                  size: 20, color: AppTheme.textSecondary)),
          if (_svc.accountList.length > 1)
            IconButton(
                onPressed: _showAccountSwitcher,
                icon: const Icon(Icons.switch_account,
                    size: 20, color: AppTheme.accent)),
          IconButton(
              tooltip: 'Remove GitHub access',
              onPressed: _logout,
              icon: const Icon(Icons.logout,
                  size: 18, color: AppTheme.error)),
        ]),
      );

  Widget _buildAccountSwitcher() {
    final avatarUrl = _svc.activeSession?.avatarUrl ?? '';
    return InkWell(
      onTap: _svc.accountList.length > 1 ? _showAccountSwitcher : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          gradient: avatarUrl.isEmpty ? AppTheme.primaryGradient : null,
          borderRadius: BorderRadius.circular(10),
          image: avatarUrl.isNotEmpty
              ? DecorationImage(
                  image: NetworkImage(avatarUrl), fit: BoxFit.cover)
              : null,
        ),
        child: avatarUrl.isEmpty
            ? Center(
                child: Text(
                    (_svc.currentUser ?? 'G')[0].toUpperCase(),
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)))
            : null,
      ),
    );
  }

  void _showAccountSwitcher() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _sheetHandle(),
          const SizedBox(height: 16),
          const Text('Switch Account',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary)),
          const SizedBox(height: 16),
          ..._svc.accountList.map((username) {
            final isActive = username == _svc.currentUser;
            return ListTile(
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: AppTheme.accentGradient,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                    child: Text(username[0].toUpperCase(),
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white))),
              ),
              title: Text(username,
                  style: TextStyle(
                      color: isActive ? AppTheme.primary : AppTheme.textPrimary,
                      fontWeight:
                          isActive ? FontWeight.w700 : FontWeight.w500)),
              trailing: isActive
                  ? const Icon(Icons.check_circle, color: AppTheme.success)
                  : null,
              onTap: () async {
                Navigator.pop(ctx);
                if (!isActive) {
                  setState(() => _loading = true);
                  await _svc.switchAccount(username);
                  await _loadRepos();
                  setState(() {
                    _issues.clear();
                    _prs.clear();
                    _notifications.clear();
                    _loading = false;
                  });
                  _toast('Switched to \$username');
                }
              },
            );
          }),
          const Divider(color: AppTheme.divider),
          ListTile(
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.surfaceHover,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border),
              ),
              child: const Icon(Icons.add, color: AppTheme.textSecondary),
            ),
            title: const Text('Add Account',
                style: TextStyle(color: AppTheme.textSecondary)),
            onTap: () {
              Navigator.pop(ctx);
              _showAddAccountSheet();
            },
          ),
        ]),
      ),
    );
  }

  void _showAddAccountSheet() {
    final addTokenCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          top: 20,
          left: 20,
          right: 20,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _sheetHandle(),
          const SizedBox(height: 16),
          const Text('Add Another Account',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary)),
          const SizedBox(height: 16),
          TextField(
            controller: addTokenCtrl,
            obscureText: true,
            style: const TextStyle(
                color: AppTheme.textPrimary, fontFamily: AppTheme.fontCode),
            decoration: _inputDecoration('ghp_xxxxxxxxxxxxxxxxxxxx',
                icon: Icons.vpn_key),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                final token = addTokenCtrl.text.trim();
                if (token.isEmpty) return;
                Navigator.pop(ctx);
                setState(() => _loading = true);
                try {
                  final ok = await _svc.authenticate(token);
                  if (ok) {
                    await _loadRepos();
                    setState(() => _loading = false);
                    _toast('Account added');
                  } else {
                    setState(() => _loading = false);
                    _toast('Invalid token', isError: true);
                  }
                } catch (e) {
                  setState(() => _loading = false);
                  _toast('Failed: \$e', isError: true);
                }
              },
              icon: const Icon(Icons.login, size: 18),
              label: const Text('Connect'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ]),
      ),
    );
  }


  // ═══════════════════════════════════════════════════════════════════════════
  // REPOSITORIES TAB (Enhanced)
  // ═══════════════════════════════════════════════════════════════════════════

  // Language color map for popular programming languages
  static final Map<String, Color> _languageColors = {
    'Dart': const Color(0xFF00B4AB),
    'Python': const Color(0xFF3572A5),
    'JavaScript': const Color(0xFFF1E05A),
    'TypeScript': const Color(0xFF3178C6),
    'Go': const Color(0xFF00ADD8),
    'Rust': const Color(0xFFDEA584),
    'Java': const Color(0xFFB07219),
    'C++': const Color(0xFFF34B7D),
    'C': const Color(0xFF555555),
    'C#': const Color(0xFF178600),
    'Swift': const Color(0xFFFFAC45),
    'Kotlin': const Color(0xFFA97BFF),
    'Ruby': const Color(0xFF701516),
    'PHP': const Color(0xFF4F5D95),
    'HTML': const Color(0xFFE34C26),
    'CSS': const Color(0xFF563D7C),
    'Shell': const Color(0xFF89E051),
    'Lua': const Color(0xFF000080),
    'Scala': const Color(0xFFC22D40),
    'Elixir': const Color(0xFF6E4A7E),
    'Vue': const Color(0xFF41B883),
    'Flutter': const Color(0xFF54C5F8),
  };

  static final List<String> _popularLanguages = [
    'Dart', 'Python', 'JavaScript', 'TypeScript', 'Go', 'Rust', 'Java', 'C++',
    'Swift', 'Kotlin', 'Ruby', 'Vue'
  ];

  Widget _buildReposTab() {
    // Apply language filter to displayed repos
    var display = _repos;
    if (_repoLanguageFilter != null) {
      display = display.where((r) {
        // Check if repo's language matches filter
        return r.language?.toLowerCase() ==
                _repoLanguageFilter!.toLowerCase() ||
            r.name.toLowerCase().contains(_repoLanguageFilter!.toLowerCase());
      }).toList();
    }

    // Sort repos
    switch (_repoSort) {
      case 'name_asc':
        display.sort((a, b) => a.name.compareTo(b.name));
      case 'name_desc':
        display.sort((a, b) => b.name.compareTo(a.name));
      case 'stars':
        display.sort((a, b) => b.stars.compareTo(a.stars));
      case 'updated':
        // Already sorted by pushed from API
        break;
    }

    // Search overlay
    final isSearching = _searchCtrl.text.isNotEmpty;
    final searchDisplay = isSearching
        ? _searchResults
            .map((r) => GitHubRepo.fromGitHubApi(r as Map<String, dynamic>))
            .toList()
        : <GitHubRepo>[];

    if (display.isEmpty && !_searching && !isSearching && _repos.isEmpty) {
      return _buildFirstTimeEmpty();
    }

    return Column(children: [
      // Ownership filter chips
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _filterChip('all', 'All', _repoFilter, (v) {
              setState(() => _repoFilter = v);
              _loadRepos();
            }),
            const SizedBox(width: 8),
            _filterChip('owner', 'Owned', _repoFilter, (v) {
              setState(() => _repoFilter = v);
              _loadRepos();
            }),
            const SizedBox(width: 8),
            _filterChip('member', 'Member', _repoFilter, (v) {
              setState(() => _repoFilter = v);
              _loadRepos();
            }),
            const SizedBox(width: 8),
            _filterChip('collaborator', 'Collab', _repoFilter, (v) {
              setState(() => _repoFilter = v);
              _loadRepos();
            }),
          ]),
        ),
      ),
      // Sort + Language filter
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(children: [
          // Sort dropdown
          Expanded(
            child: InkWell(
              onTap: _showSortMenu,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.surface.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.sort, size: 14, color: AppTheme.textTertiary),
                  const SizedBox(width: 6),
                  Text(_sortLabel(_repoSort),
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary)),
                  const Icon(Icons.keyboard_arrow_down,
                      size: 16, color: AppTheme.textTertiary),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Language filter dropdown
          Expanded(
            child: InkWell(
              onTap: _showLanguageFilterMenu,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _repoLanguageFilter != null
                      ? AppTheme.primary.withOpacity(0.15)
                      : AppTheme.surface.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: _repoLanguageFilter != null
                          ? AppTheme.primary.withOpacity(0.5)
                          : AppTheme.border),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.code,
                      size: 14,
                      color: _repoLanguageFilter != null
                          ? AppTheme.primary
                          : AppTheme.textTertiary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                        _repoLanguageFilter ?? 'Language',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            color: _repoLanguageFilter != null
                                ? AppTheme.primary
                                : AppTheme.textSecondary)),
                  ),
                  if (_repoLanguageFilter != null)
                    InkWell(
                      onTap: () {
                        setState(() => _repoLanguageFilter = null);
                      },
                      child: const Icon(Icons.close,
                          size: 14, color: AppTheme.primary),
                    )
                  else
                    const Icon(Icons.keyboard_arrow_down,
                        size: 16, color: AppTheme.textTertiary),
                ]),
              ),
            ),
          ),
        ]),
      ),
      // Language quick chips
      if (!isSearching)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              ..._popularLanguages.take(8).map((lang) {
                final isSelected = _repoLanguageFilter == lang;
                final color = _languageColors[lang] ?? AppTheme.textTertiary;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: InkWell(
                    onTap: () {
                      setState(() => _repoLanguageFilter =
                          isSelected ? null : lang);
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? color.withOpacity(0.2)
                            : AppTheme.surface.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: isSelected
                                ? color.withOpacity(0.5)
                                : AppTheme.border,
                            width: 0.8),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                              color: color, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 5),
                        Text(lang,
                            style: TextStyle(
                                fontSize: 11,
                                color: isSelected ? color : AppTheme.textSecondary,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400)),
                      ]),
                    ),
                  ),
                );
              }),
            ]),
          ),
        ),
      // Search indicator
      if (isSearching)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(children: [
            const Icon(Icons.search, size: 14, color: AppTheme.primary),
            const SizedBox(width: 6),
            Text('Search: "${_searchCtrl.text}"',
                style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w500)),
            const Spacer(),
            InkWell(
              onTap: () {
                setState(() {
                  _searchCtrl.clear();
                  _searchResults.clear();
                });
              },
              child: const Icon(Icons.close, size: 16, color: AppTheme.textTertiary),
            ),
          ]),
        ),
      // Repo list
      Expanded(
        child: RefreshIndicator(
          onRefresh: _loadRepos,
          color: AppTheme.primary,
          backgroundColor: AppTheme.surface,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            itemCount: isSearching ? searchDisplay.length : display.length,
            itemBuilder: (_, i) => isSearching
                ? _repoCard(searchDisplay[i])
                : _repoCard(display[i]),
          ),
        ),
      ),
    ]);
  }

  Widget _buildFirstTimeEmpty() => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    gradient: AppTheme.accentGradient,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                          color: AppTheme.accent.withOpacity(0.2),
                          blurRadius: 24,
                          spreadRadius: 4)
                    ],
                  ),
                  child:
                      const Icon(Icons.folder_open, size: 48, color: Colors.white),
                ),
                const SizedBox(height: 24),
                Text('Welcome to GitHub!',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                    'You don\'t have any repositories yet. Create your first one to get started.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppTheme.textSecondary)),
                const SizedBox(height: 8),
                Text('Or tap the search icon to find repositories.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppTheme.textTertiary)),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _showCreateRepoSheet,
                  icon: const Icon(Icons.create_new_folder),
                  label: const Text('Create Repository'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 14),
                  ),
                ),
              ]),
        ),
      );

  Widget _repoCard(GitHubRepo repo) {
    final langColor = _languageColors[repo.language] ?? AppTheme.textTertiary;
    final pushedAgo = _ago(repo.lastSynced);
    return GlassCardWidget(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      borderRadius: 12,
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => GitHubRepoScreen(
                  repoName: repo.name,
                  owner: repo.owner,
                  description: repo.description,
                  language: repo.language))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(repo.isPrivate ? Icons.lock_outline : Icons.folder_outlined,
              size: 16,
              color: repo.isPrivate ? AppTheme.warning : AppTheme.accent),
          const SizedBox(width: 8),
          Expanded(
              child: Text(repo.fullName,
                  style: const TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary),
                  overflow: TextOverflow.ellipsis)),
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.star, size: 13, color: AppTheme.warning),
            const SizedBox(width: 3),
            Text('${repo.stars}',
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textTertiary)),
          ]),
        ]),
        if (repo.description.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(repo.description,
              style: const TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 12,
                  color: AppTheme.textSecondary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis)
        ],
        const SizedBox(height: 10),
        Row(children: [
          // Language dot
          if (repo.language != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration:
                  BoxDecoration(color: langColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
            Text(repo.language!,
                style: TextStyle(
                    fontSize: 11,
                    fontFamily: AppTheme.fontCode,
                    color: langColor)),
            const SizedBox(width: 12),
          ],
          // Default branch
          Text(repo.defaultBranch,
              style: const TextStyle(
                  fontSize: 11,
                  fontFamily: AppTheme.fontCode,
                  color: AppTheme.textTertiary)),
          const Spacer(),
          // Fork count
          if (repo.forks != null && repo.forks! > 0) ...[
            const Icon(Icons.call_split,
                size: 12, color: AppTheme.textTertiary),
            const SizedBox(width: 3),
            Text('${repo.forks}',
                style: const TextStyle(
                    fontSize: 11, color: AppTheme.textTertiary)),
            const SizedBox(width: 10),
          ],
          // Last pushed
          const Icon(Icons.schedule, size: 11, color: AppTheme.textTertiary),
          const SizedBox(width: 3),
          Text(pushedAgo,
              style: const TextStyle(
                  fontSize: 10, color: AppTheme.textTertiary)),
        ]),
        const SizedBox(height: 8),
        // Action buttons
        Row(children: [
          _miniAction(Icons.content_copy, 'Clone', () => _cloneSheet(repo)),
          const SizedBox(width: 12),
          _miniAction(Icons.call_split, 'Fork', () => _forkRepo(repo)),
          const SizedBox(width: 12),
          _miniAction(Icons.star_border, 'Star', () => _starRepo(repo)),
          const Spacer(),
          _miniAction(Icons.open_in_browser, 'Open',
              () => launchUrl(Uri.parse(repo.webUrl))),
        ]),
      ]),
    );
  }

  String _sortLabel(String sort) => switch (sort) {
        'name_asc' => 'Name \u2191',
        'name_desc' => 'Name \u2193',
        'pushed' => 'Recent Push',
        'updated' => 'Updated',
        'stars' => 'Most Stars',
        _ => 'Recent Push',
      };

  void _showSortMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _sheetHandle(),
          const SizedBox(height: 12),
          const Text('Sort Repositories',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary)),
          const SizedBox(height: 12),
          ...[
            ('pushed', 'Recently Pushed'),
            ('updated', 'Recently Updated'),
            ('stars', 'Most Stars'),
            ('name_asc', 'Name (A-Z)'),
            ('name_desc', 'Name (Z-A)'),
          ].map((item) {
            final (value, label) = item;
            final selected = _repoSort == value;
            return ListTile(
              dense: true,
              title: Text(label,
                  style: TextStyle(
                      color: selected ? AppTheme.primary : AppTheme.textPrimary,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w400)),
              trailing: selected
                  ? const Icon(Icons.check, color: AppTheme.primary, size: 20)
                  : null,
              onTap: () {
                setState(() => _repoSort = value);
                Navigator.pop(ctx);
              },
            );
          }),
        ]),
      ),
    );
  }

  void _showLanguageFilterMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _sheetHandle(),
          const SizedBox(height: 12),
          const Text('Filter by Language',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary)),
          const SizedBox(height: 12),
          ListTile(
            dense: true,
            title: const Text('All Languages',
                style: TextStyle(color: AppTheme.textPrimary)),
            trailing: _repoLanguageFilter == null
                ? const Icon(Icons.check, color: AppTheme.primary, size: 20)
                : null,
            onTap: () {
              setState(() => _repoLanguageFilter = null);
              Navigator.pop(ctx);
            },
          ),
          const Divider(color: AppTheme.divider, height: 8),
          ..._popularLanguages.map((lang) {
            final selected = _repoLanguageFilter == lang;
            final color = _languageColors[lang] ?? AppTheme.textTertiary;
            return ListTile(
              dense: true,
              leading: Container(
                width: 10,
                height: 10,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              title: Text(lang,
                  style: TextStyle(
                      color:
                          selected ? AppTheme.primary : AppTheme.textPrimary,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w400)),
              trailing: selected
                  ? const Icon(Icons.check, color: AppTheme.primary, size: 20)
                  : null,
              onTap: () {
                setState(() => _repoLanguageFilter = lang);
                Navigator.pop(ctx);
              },
            );
          }),
        ]),
      ),
    );
  }


  // ═══════════════════════════════════════════════════════════════════════════
  // ISSUES TAB (Enhanced)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildIssuesTab() {
    if (_issues.isEmpty && !_loading) {
      return _empty(Icons.check_circle_outline, 'No issues found',
          'All clear! Create an issue to get started.');
    }
    return Column(children: [
      // State filter chips
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _filterChip('open', 'Open', _issueFilter, (v) {
              setState(() => _issueFilter = v);
              _loadIssues();
            }),
            const SizedBox(width: 8),
            _filterChip('closed', 'Closed', _issueFilter, (v) {
              setState(() => _issueFilter = v);
              _loadIssues();
            }),
            const SizedBox(width: 8),
            _filterChip('all', 'All', _issueFilter, (v) {
              setState(() => _issueFilter = v);
              _loadIssues();
            }),
            const SizedBox(width: 8),
            // Label filter chip
            if (_repoLabels.isNotEmpty)
              InkWell(
                onTap: _showIssueLabelFilter,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _issueLabelFilter != null
                        ? AppTheme.primary.withOpacity(0.2)
                        : AppTheme.surface.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: _issueLabelFilter != null
                            ? AppTheme.primary.withOpacity(0.5)
                            : AppTheme.border,
                        width: 1),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.label_outline,
                        size: 12,
                        color: _issueLabelFilter != null
                            ? AppTheme.primary
                            : AppTheme.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                        _issueLabelFilter ??
                            'Labels (${_repoLabels.length})',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: _issueLabelFilter != null
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: _issueLabelFilter != null
                                ? AppTheme.primary
                                : AppTheme.textSecondary)),
                    if (_issueLabelFilter != null) ...[
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () {
                          setState(() => _issueLabelFilter = null);
                          _loadIssues();
                        },
                        child: const Icon(Icons.close,
                            size: 12, color: AppTheme.primary),
                      ),
                    ],
                  ]),
                ),
              ),
          ]),
        ),
      ),
      // Assignee + Milestone filters
      if (_issueLabelFilter != null || _issueAssigneeFilter != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(children: [
            if (_issueLabelFilter != null)
              _activeFilterChip(
                  'Label: $_issueLabelFilter',
                  () => setState(() {
                        _issueLabelFilter = null;
                        _loadIssues();
                      })),
          ]),
        ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _loadIssues,
          color: AppTheme.primary,
          backgroundColor: AppTheme.surface,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            itemCount: _issues.length,
            itemBuilder: (_, i) => _issueCard(_issues[i]),
          ),
        ),
      ),
    ]);
  }

  Widget _activeFilterChip(String label, VoidCallback onRemove) => Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 10,
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w500)),
          const SizedBox(width: 4),
          InkWell(
            onTap: onRemove,
            child: const Icon(Icons.close, size: 12, color: AppTheme.primary),
          ),
        ]),
      );

  void _showIssueLabelFilter() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _sheetHandle(),
          const SizedBox(height: 12),
          const Text('Filter by Label',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary)),
          const SizedBox(height: 12),
          ListTile(
            dense: true,
            title: const Text('All Labels',
                style: TextStyle(color: AppTheme.textPrimary)),
            trailing: _issueLabelFilter == null
                ? const Icon(Icons.check, color: AppTheme.primary, size: 20)
                : null,
            onTap: () {
              setState(() => _issueLabelFilter = null);
              _loadIssues();
              Navigator.pop(ctx);
            },
          ),
          const Divider(color: AppTheme.divider, height: 8),
          ..._repoLabels.map((label) {
            final name = label['name'] as String? ?? '';
            final color = _hexColor(label['color'] as String? ?? '666666');
            final selected = _issueLabelFilter == name;
            return ListTile(
              dense: true,
              leading: Container(
                width: 10,
                height: 10,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              title: Text(name,
                  style: TextStyle(
                      color:
                          selected ? AppTheme.primary : AppTheme.textPrimary,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w400)),
              trailing: selected
                  ? const Icon(Icons.check, color: AppTheme.primary, size: 20)
                  : null,
              onTap: () {
                setState(() => _issueLabelFilter = name);
                _loadIssues();
                Navigator.pop(ctx);
              },
            );
          }),
        ]),
      ),
    );
  }

  Widget _issueCard(dynamic issue) {
    final open = issue['state'] == 'open';
    final labels = (issue['labels'] as List<dynamic>?) ?? [];
    final num = issue['number'] as int? ?? 0;
    final title = issue['title'] as String? ?? 'Untitled';
    final author =
        ((issue['user'] as Map<String, dynamic>?)?.cast<String, dynamic>())?[
                'login']
            as String? ??
        'unknown';
    final created = issue['created_at'] != null
        ? DateTime.parse(issue['created_at'] as String)
        : DateTime.now();
    final comments = issue['comments'] as int? ?? 0;
    final assignees = (issue['assignees'] as List<dynamic>?) ?? [];

    return GlassCardWidget(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      borderRadius: 12,
      onTap: () => _navigateToIssueDetail(issue),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(open ? Icons.error_outline : Icons.check_circle,
              size: 18, color: open ? AppTheme.success : AppTheme.textTertiary),
          const SizedBox(width: 8),
          Text('#$num',
              style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textTertiary,
                  fontFamily: AppTheme.fontCode)),
          const Spacer(),
          Text(_ago(created),
              style: const TextStyle(
                  fontSize: 11, color: AppTheme.textTertiary)),
        ]),
        const SizedBox(height: 8),
        Text(title,
            style: const TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary)),
        if (labels.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
              spacing: 6,
              runSpacing: 4,
              children: labels.map<Widget>((l) {
                final name = l['name'] as String? ?? '';
                final c = _hexColor(l['color'] as String? ?? '666666');
                return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: c.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: c.withOpacity(0.3), width: 0.5)),
                    child: Text(name,
                        style: TextStyle(
                            fontSize: 10,
                            color: c,
                            fontWeight: FontWeight.w500)));
              }).toList())
        ],
        const SizedBox(height: 10),
        Row(children: [
          _avatar(author, gradient: AppTheme.accentGradient),
          const SizedBox(width: 6),
          Text(author,
              style: const TextStyle(
                  fontSize: 12, color: AppTheme.textSecondary)),
          const Spacer(),
          // Assignees
          if (assignees.isNotEmpty) ...[
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.person_outline,
                  size: 12, color: AppTheme.textTertiary),
              const SizedBox(width: 2),
              Text('${assignees.length}',
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textTertiary)),
            ]),
            const SizedBox(width: 10),
          ],
          // Comments count
          if (comments > 0)
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.comment_outlined,
                  size: 13, color: AppTheme.textTertiary),
              const SizedBox(width: 3),
              Text('$comments',
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textTertiary)),
            ]),
        ]),
      ]),
    );
  }

  void _navigateToIssueDetail(dynamic issue) {
    if (_repos.isEmpty) return;
    final num = issue['number'] as int? ?? 0;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GitHubIssueDetailScreen(
          owner: _repos.first.owner,
          repo: _repos.first.name,
          issueNumber: num,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PULL REQUESTS TAB (Enhanced)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPRsTab() {
    if (_prs.isEmpty && !_loading) {
      return _empty(Icons.call_merge, 'No pull requests',
          'Create a pull request to propose changes.');
    }
    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _filterChip('open', 'Open', _prFilter, (v) {
              setState(() => _prFilter = v);
              _loadPRs();
            }),
            const SizedBox(width: 8),
            _filterChip('closed', 'Closed', _prFilter, (v) {
              setState(() => _prFilter = v);
              _loadPRs();
            }),
            const SizedBox(width: 8),
            _filterChip('all', 'All', _prFilter, (v) {
              setState(() => _prFilter = v);
              _loadPRs();
            }),
          ]),
        ),
      ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _loadPRs,
          color: AppTheme.primary,
          backgroundColor: AppTheme.surface,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            itemCount: _prs.length,
            itemBuilder: (_, i) => _prCard(_prs[i]),
          ),
        ),
      ),
    ]);
  }

  Widget _prCard(dynamic pr) {
    final state = pr['state'] as String? ?? 'open';
    final merged = pr['merged'] == true;
    final draft = pr['draft'] == true;
    final num = pr['number'] as int? ?? 0;
    final title = pr['title'] as String? ?? 'Untitled';
    final author =
        ((pr['user'] as Map<String, dynamic>?)?.cast<String, dynamic>())?[
                'login']
            as String? ??
        'unknown';
    final head =
        ((pr['head'] as Map<String, dynamic>?)?.cast<String, dynamic>())?[
                'ref']
            as String? ??
        'unknown';
    final base =
        ((pr['base'] as Map<String, dynamic>?)?.cast<String, dynamic>())?[
                'ref']
            as String? ??
        'unknown';

    // CI status
    final ciStatus = _getCIStatus(pr);

    // Review state
    final reviewState = pr['review_state'] as String?;

    late final Color sColor;
    late final IconData sIcon;
    if (merged) {
      sColor = AppTheme.primary;
      sIcon = Icons.merge_type;
    } else if (draft) {
      sColor = AppTheme.textTertiary;
      sIcon = Icons.drafts;
    } else if (state == 'open') {
      sColor = AppTheme.success;
      sIcon = Icons.call_merge;
    } else {
      sColor = AppTheme.error;
      sIcon = Icons.cancel;
    }

    return GlassCardWidget(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      borderRadius: 12,
      onTap: () => _navigateToPRReview(pr),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(sIcon, size: 18, color: sColor),
          const SizedBox(width: 8),
          Text('#$num',
              style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textTertiary,
                  fontFamily: AppTheme.fontCode)),
          const SizedBox(width: 8),
          // CI status indicator
          if (ciStatus != null) ...[
            _ciStatusIcon(ciStatus),
            const SizedBox(width: 6),
          ],
          const Spacer(),
          // Review status badge
          if (reviewState != null)
            _reviewStatusBadge(reviewState)
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                  color: sColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: sColor.withOpacity(0.3), width: 0.5)),
              child: Text(merged ? 'MERGED' : draft ? 'DRAFT' : state.toUpperCase(),
                  style: TextStyle(
                      fontSize: 9,
                      color: sColor,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5)),
            ),
        ]),
        const SizedBox(height: 8),
        Text(title,
            style: const TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary)),
        const SizedBox(height: 8),
        // Branch info
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
              color: AppTheme.surfaceHover,
              borderRadius: BorderRadius.circular(8)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(head,
                style: const TextStyle(
                    fontSize: 11,
                    fontFamily: AppTheme.fontCode,
                    color: AppTheme.accent)),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward,
                size: 12, color: AppTheme.textTertiary),
            const SizedBox(width: 8),
            Text(base,
                style: const TextStyle(
                    fontSize: 11,
                    fontFamily: AppTheme.fontCode,
                    color: AppTheme.textSecondary)),
          ]),
        ),
        const SizedBox(height: 10),
        Row(children: [
          _avatar(author, gradient: AppTheme.primaryGradient),
          const SizedBox(width: 6),
          Text(author,
              style: const TextStyle(
                  fontSize: 12, color: AppTheme.textSecondary)),
          const Spacer(),
          // PR comments
          if ((pr['comments'] as int? ?? 0) > 0) ...[
            const Icon(Icons.comment_outlined,
                size: 12, color: AppTheme.textTertiary),
            const SizedBox(width: 3),
            Text('${pr['comments']}',
                style: const TextStyle(
                    fontSize: 11, color: AppTheme.textTertiary)),
            const SizedBox(width: 10),
          ],
          // Changed files count
          if ((pr['changed_files'] as int? ?? 0) > 0)
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.insert_drive_file_outlined,
                  size: 12, color: AppTheme.textTertiary),
              const SizedBox(width: 3),
              Text('${pr['changed_files']}',
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textTertiary)),
            ]),
        ]),
      ]),
    );
  }

  String? _getCIStatus(dynamic pr) {
    // Check for CI status from various API fields
    if (pr['statuses_url'] != null) {
      // Could fetch real CI status from API
      // For now, return simulated status based on mergeable state
      final mergeableState = pr['mergeable_state'] as String?;
      if (mergeableState == 'clean') return 'success';
      if (mergeableState == 'dirty') return 'failure';
      if (mergeableState == 'unstable') return 'pending';
    }
    final state = pr['state'] as String?;
    if (state == 'closed' && pr['merged'] != true) return null;
    return null;
  }

  Widget _ciStatusIcon(String status) {
    late final IconData icon;
    late final Color color;
    switch (status) {
      case 'success':
        icon = Icons.check_circle;
        color = AppTheme.success;
      case 'failure':
        icon = Icons.cancel;
        color = AppTheme.error;
      case 'pending':
        icon = Icons.pending;
        color = AppTheme.warning;
      default:
        icon = Icons.circle;
        color = AppTheme.textTertiary;
    }
    return Icon(icon, size: 16, color: color);
  }

  Widget _reviewStatusBadge(String state) {
    late final Color color;
    late final String label;
    late final IconData icon;
    switch (state) {
      case 'APPROVED':
        color = AppTheme.success;
        label = 'APPROVED';
        icon = Icons.check_circle;
      case 'CHANGES_REQUESTED':
        color = AppTheme.error;
        label = 'CHANGES';
        icon = Icons.cancel;
      case 'COMMENTED':
        color = AppTheme.info;
        label = 'REVIEWED';
        icon = Icons.comment;
      default:
        color = AppTheme.textTertiary;
        label = 'PENDING';
        icon = Icons.pending;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.3), width: 0.5)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 10, color: color),
        const SizedBox(width: 3),
        Text(label,
            style: TextStyle(
                fontSize: 8,
                color: color,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5)),
      ]),
    );
  }

  void _navigateToPRReview(dynamic pr) {
    if (_repos.isEmpty) return;
    final num = pr['number'] as int? ?? 0;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GitHubPrReviewScreen(
          owner: _repos.first.owner,
          repo: _repos.first.name,
          pullNumber: num,
        ),
      ),
    );
  }


  // ═══════════════════════════════════════════════════════════════════════════
  // NOTIFICATIONS TAB (Enhanced)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildNotificationsTab() {
    if (_notifications.isEmpty) {
      return _empty(Icons.notifications_off_outlined, 'No new notifications',
          'You\'re all caught up!');
    }

    // Group notifications by repository
    final grouped = <String, List<dynamic>>{};
    for (final n in _notifications) {
      final repoName =
          ((n['repository'] as Map<String, dynamic>?)?.cast<String, dynamic>())?[
                  'full_name']
              as String? ??
          'unknown/repo';
      grouped.putIfAbsent(repoName, () => []).add(n);
    }

    return Column(children: [
      // Mark all read + count
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          TextButton.icon(
            onPressed: _markAllNotificationsRead,
            icon: const Icon(Icons.done_all, size: 16),
            label: const Text('Mark all read', style: TextStyle(fontSize: 12)),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.error.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$_unreadCount unread',
                style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.error,
                    fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _loadNotifications,
          color: AppTheme.primary,
          backgroundColor: AppTheme.surface,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            itemCount: grouped.length,
            itemBuilder: (_, groupIndex) {
              final repoName = grouped.keys.elementAt(groupIndex);
              final items = grouped[repoName]!;
              return _buildNotificationGroup(repoName, items);
            },
          ),
        ),
      ),
    ]);
  }

  Widget _buildNotificationGroup(String repoName, List<dynamic> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Repo header
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
          child: Row(children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppTheme.primary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(repoName,
                style: const TextStyle(
                    fontSize: 13,
                    fontFamily: AppTheme.fontCode,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('${items.length}',
                  style: const TextStyle(
                      fontSize: 10,
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
        // Notification items with swipe-to-dismiss
        ...items.map((n) => _buildDismissibleNotification(n)),
        const Divider(color: AppTheme.divider, height: 16),
      ],
    );
  }

  Widget _buildDismissibleNotification(dynamic n) {
    final id = n['id'] as String? ?? '';
    return Dismissible(
      key: Key('notif_$id'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: AppTheme.success.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.done_all, color: AppTheme.success, size: 20),
            SizedBox(width: 6),
            Text('Mark Read',
                style: TextStyle(
                    color: AppTheme.success,
                    fontWeight: FontWeight.w600,
                    fontSize: 12)),
          ],
        ),
      ),
      onDismissed: (_) async {
        try {
          await _svc.markNotificationRead(id);
          setState(() {
            _notifications.remove(n);
            _unreadCount = (_unreadCount - 1).clamp(0, 999);
          });
        } catch (e) {
          _toast('Failed: \$e', isError: true);
        }
      },
      child: _notifCard(n),
    );
  }

  Widget _notifCard(dynamic n) {
    final sub = (n['subject'] as Map<String, dynamic>?)?.cast<String, dynamic>();
    final title = sub?['title'] as String? ?? 'Notification';
    final type = sub?['type'] as String? ?? 'Unknown';
    final repoName =
        ((n['repository'] as Map<String, dynamic>?)?.cast<String, dynamic>())?[
                'full_name']
            as String? ??
        'unknown/repo';
    final updated = n['updated_at'] != null
        ? DateTime.parse(n['updated_at'] as String)
        : DateTime.now();
    final reason = n['reason'] as String? ?? '';

    late final IconData tIcon;
    late final Color tColor;
    switch (type) {
      case 'PullRequest':
        tIcon = Icons.call_merge;
        tColor = AppTheme.primary;
      case 'Issue':
        tIcon = Icons.error_outline;
        tColor = AppTheme.success;
      case 'Release':
        tIcon = Icons.new_releases_outlined;
        tColor = AppTheme.accent;
      case 'Commit':
        tIcon = Icons.commit;
        tColor = AppTheme.info;
      case 'Discussion':
        tIcon = Icons.forum_outlined;
        tColor = AppTheme.warning;
      default:
        tIcon = Icons.notifications_none;
        tColor = AppTheme.textTertiary;
    }

    return GlassCardWidget(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      borderRadius: 10,
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
              color: tColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(tIcon, size: 18, color: tColor),
        ),
        const SizedBox(width: 12),
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(title,
                  style: const TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textPrimary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Row(children: [
                Text(type,
                    style: TextStyle(
                        fontSize: 10,
                        fontFamily: AppTheme.fontCode,
                        color: tColor,
                        fontWeight: FontWeight.w500)),
                const SizedBox(width: 8),
                if (reason.isNotEmpty)
                  Text(reason,
                      style: const TextStyle(
                          fontSize: 10, color: AppTheme.textTertiary)),
                const Spacer(),
                Text(_ago(updated),
                    style: const TextStyle(
                        fontSize: 10, color: AppTheme.textTertiary)),
              ]),
            ])),
        IconButton(
            onPressed: () async {
              final id = n['id'] as String?;
              if (id != null) {
                await _svc.markNotificationRead(id);
                setState(() {
                  _notifications.remove(n);
                  _unreadCount = (_unreadCount - 1).clamp(0, 999);
                });
              }
            },
            icon: const Icon(Icons.done, size: 18, color: AppTheme.success)),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BOTTOM SHEETS & DIALOGS
  // ═══════════════════════════════════════════════════════════════════════════

  void _showSearchSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(top: BorderSide(color: AppTheme.border)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            top: 16,
            left: 16,
            right: 16,
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            TextField(
              controller: _searchCtrl,
              autofocus: true,
              style: const TextStyle(color: AppTheme.textPrimary),
              onSubmitted: (_) async {
                setSt(() {});
                await _search();
                setSt(() {});
              },
              decoration: _inputDecoration('Search repositories on GitHub...',
                  icon: Icons.search,
                  suffix: _searching
                      ? Container(
                          width: 20,
                          height: 20,
                          margin: const EdgeInsets.all(12),
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  AppTheme.primary)))
                      : IconButton(
                          icon: const Icon(Icons.arrow_forward,
                              color: AppTheme.primary),
                          onPressed: () async {
                            setSt(() {});
                            await _search();
                            setSt(() {});
                          })),
            ),
            if (_searchResults.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 400,
                child: ListView.builder(
                  itemCount: _searchResults.length,
                  itemBuilder: (_, i) {
                    final r = _searchResults[i];
                    final lang = r['language'] as String?;
                    final langColor = _languageColors[lang] ?? AppTheme.textTertiary;
                    return ListTile(
                      dense: true,
                      leading: Icon(
                          r['private'] == true
                              ? Icons.lock
                              : Icons.folder_outlined,
                          size: 18,
                          color: AppTheme.textSecondary),
                      title: Text(r['full_name'] as String? ?? 'Unknown',
                          style: const TextStyle(
                              fontSize: 13,
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w500)),
                      subtitle: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (lang != null) ...[
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: langColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(lang,
                                style: const TextStyle(
                                    fontSize: 10, color: AppTheme.textTertiary)),
                            const SizedBox(width: 8),
                          ],
                          Text(r['description'] as String? ?? '',
                              style: const TextStyle(
                                  fontSize: 11, color: AppTheme.textTertiary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                      trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star,
                                size: 13, color: AppTheme.warning),
                            const SizedBox(width: 3),
                            Text('${r['stargazers_count'] ?? 0}',
                                style: const TextStyle(
                                    fontSize: 11, color: AppTheme.textTertiary)),
                          ]),
                      onTap: () {
                        Navigator.pop(ctx);
                        final owner =
                            (r['owner'] as Map<String, dynamic>?)?['login']
                                    as String? ??
                                '';
                        final name = r['name'] as String? ?? '';
                        if (owner.isNotEmpty && name.isNotEmpty) {
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => GitHubRepoScreen(
                                      repoName: name,
                                      owner: owner,
                                      description:
                                          r['description'] as String?,
                                      language: r['language'] as String?)));
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  void _showCreateRepoSheet() {
    final intentCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    bool priv = false;
    bool initReadme = false;
    bool polishing = false;
    String? polishNote;
    String selectedLang = 'Dart';
    final polishService = RepoIntentPolishService();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            top: 20,
            left: 20,
            right: 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sheetHandle(),
                const SizedBox(height: 20),
                const Text('Create Repository',
                    style: TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary)),
                const SizedBox(height: 16),
                TextField(
                    controller: intentCtrl,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    maxLines: 3,
                    decoration: _inputDecoration('Repository intent').copyWith(
                        labelText: 'Intent',
                        hintText: 'Describe the repo in one sentence, then polish it into a clean GitHub draft.')),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: polishing
                        ? null
                        : () async {
                      final intent = intentCtrl.text.trim();
                      if (intent.isEmpty) {
                        _toast('Describe the repository intent first.', isError: true);
                        return;
                      }
                      setSt(() {
                        polishing = true;
                        polishNote = null;
                      });
                      final draft = await polishService.polish(intent);
                      if (!mounted || !ctx.mounted) return;
                      setSt(() {
                        nameCtrl.text = draft.name;
                        descCtrl.text = draft.description;
                        selectedLang = draft.language;
                        priv = draft.isPrivate;
                        initReadme = draft.addReadme;
                        polishing = false;
                        polishNote = draft.usedProvider
                            ? 'AI provider generated this draft.'
                            : 'AI unavailable: ${draft.fallbackReason ?? 'using local fallback.'}';
                      });
                      _toast(draft.usedProvider ? 'Repository draft polished by AI provider.' : 'AI unavailable, used local fallback draft.');
                    },
                    icon: polishing
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.auto_fix_high_outlined, size: 16),
                    label: Text(polishing ? '润色中...' : 'AI 润色填表'),
                  ),
                ),
                if (polishNote != null) ...[
                  const SizedBox(height: 6),
                  Text(polishNote!, style: const TextStyle(color: AppTheme.textTertiary, fontSize: 12)),
                ],
                const SizedBox(height: 12),
                TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: _inputDecoration('Repository name')
                        .copyWith(labelText: 'Repository name')),
                const SizedBox(height: 12),
                TextField(
                    controller: descCtrl,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    maxLines: 2,
                    decoration: _inputDecoration('Description (optional)')
                        .copyWith(labelText: 'Description')),
                const SizedBox(height: 12),
                // Language selection
                Text('Primary Language',
                    style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ['Dart', 'Python', 'JavaScript', 'TypeScript', 'Go']
                      .map((lang) {
                    final color = _languageColors[lang] ?? AppTheme.textTertiary;
                    final isSelected = selectedLang == lang;
                    return InkWell(
                      onTap: () => setSt(() => selectedLang = lang),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? color.withOpacity(0.2)
                              : AppTheme.surfaceHover,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: isSelected
                                  ? color.withOpacity(0.5)
                                  : AppTheme.border,
                              width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                  color: color, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 5),
                            Text(lang,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: isSelected ? color : AppTheme.textSecondary)),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                    value: priv,
                    onChanged: (v) => setSt(() => priv = v),
                    title: const Text('Private repository',
                        style: TextStyle(
                            fontSize: 14, color: AppTheme.textPrimary)),
                    subtitle: const Text(
                        'Only visible to you and collaborators',
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.textTertiary)),
                    activeColor: AppTheme.primary,
                    contentPadding: EdgeInsets.zero),
                SwitchListTile(
                    value: initReadme,
                    onChanged: (v) => setSt(() => initReadme = v),
                    title: const Text('Add README',
                        style: TextStyle(
                            fontSize: 14, color: AppTheme.textPrimary)),
                    subtitle: const Text(
                        'Initialize with a README.md file',
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.textTertiary)),
                    activeColor: AppTheme.primary,
                    contentPadding: EdgeInsets.zero),
                const SizedBox(height: 20),
                SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final n = nameCtrl.text.trim();
                        if (n.isEmpty) return;
                        Navigator.pop(ctx);
                        try {
                          await _svc.createRepo(n,
                              description: descCtrl.text.trim(),
                              isPrivate: priv,
                              autoInit: initReadme);
                          _toast('Repository "$n" created');
                          await _loadRepos();
                        } catch (e) {
                          _toast('Failed to create repo: $e', isError: true);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10))),
                      child: const Text('Create Repository',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    )),
              ]),
          ),
        ),
      ),
    );
  }

  void _createIssueSheet() {
    if (_repos.isEmpty) return;
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    String repoName = _repos.first.fullName;
    // Pre-populate label filter as issue label if set
    List<String> selectedLabels = [];
    if (_issueLabelFilter != null) selectedLabels.add(_issueLabelFilter!);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            top: 20,
            left: 20,
            right: 20,
          ),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sheetHandle(),
                const SizedBox(height: 20),
                const Text('Create Issue',
                    style: TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary)),
                const SizedBox(height: 16),
                if (_repos.length > 1)
                  DropdownButtonFormField<String>(
                      value: repoName,
                      dropdownColor: AppTheme.surfaceHover,
                      style: const TextStyle(
                          color: AppTheme.textPrimary, fontSize: 14),
                      decoration: _inputDecoration('Repository')
                          .copyWith(labelText: 'Repository'),
                      items: _repos
                          .map((r) => DropdownMenuItem(
                              value: r.fullName, child: Text(r.fullName)))
                          .toList(),
                      onChanged: (v) => setSt(() => repoName = v!)),
                if (_repos.length > 1) const SizedBox(height: 12),
                TextField(
                    controller: titleCtrl,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: _inputDecoration('Title')
                        .copyWith(labelText: 'Title')),
                const SizedBox(height: 12),
                TextField(
                    controller: bodyCtrl,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    maxLines: 4,
                    decoration: _inputDecoration(
                            'Description (supports Markdown)')
                        .copyWith(labelText: 'Description')),
                const SizedBox(height: 12),
                // Label selector
                if (_repoLabels.isNotEmpty) ...[
                  Text('Labels',
                      style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _repoLabels.map<Widget>((l) {
                      final name = l['name'] as String? ?? '';
                      final color =
                          _hexColor(l['color'] as String? ?? '666666');
                      final isSelected = selectedLabels.contains(name);
                      return InkWell(
                        onTap: () => setSt(() {
                          if (isSelected) {
                            selectedLabels.remove(name);
                          } else {
                            selectedLabels.add(name);
                          }
                        }),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? color.withOpacity(0.25)
                                : color.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: isSelected
                                    ? color.withOpacity(0.6)
                                    : color.withOpacity(0.2),
                                width: 1),
                          ),
                          child: Text(name,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: isSelected ? color : color.withOpacity(0.6),
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w400)),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 20),
                SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final t = titleCtrl.text.trim();
                        if (t.isEmpty) return;
                        final p = repoName.split('/');
                        Navigator.pop(ctx);
                        try {
                          await _svc.createIssue(p[0], p[1], t,
                              body: bodyCtrl.text.trim(),
                              labels: selectedLabels.isEmpty
                                  ? null
                                  : selectedLabels);
                          _toast('Issue created');
                          if (_tabCtrl.index == 1) await _loadIssues();
                        } catch (e) {
                          _toast('Failed: \$e', isError: true);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.success,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10))),
                      child: const Text('Create Issue',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    )),
              ]),
        ),
      ),
    );
  }

  void _createPRSheet() {
    if (_repos.isEmpty) return;
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    final headCtrl = TextEditingController();
    final baseCtrl = TextEditingController(text: 'main');
    String repoName = _repos.first.fullName;
    bool draft = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            top: 20,
            left: 20,
            right: 20,
          ),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sheetHandle(),
                const SizedBox(height: 20),
                const Text('Create Pull Request',
                    style: TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary)),
                const SizedBox(height: 16),
                if (_repos.length > 1)
                  DropdownButtonFormField<String>(
                      value: repoName,
                      dropdownColor: AppTheme.surfaceHover,
                      style: const TextStyle(
                          color: AppTheme.textPrimary, fontSize: 14),
                      decoration: _inputDecoration('Repository')
                          .copyWith(labelText: 'Repository'),
                      items: _repos
                          .map((r) => DropdownMenuItem(
                              value: r.fullName, child: Text(r.fullName)))
                          .toList(),
                      onChanged: (v) => setSt(() => repoName = v!)),
                if (_repos.length > 1) const SizedBox(height: 12),
                TextField(
                    controller: titleCtrl,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: _inputDecoration('Title')
                        .copyWith(labelText: 'Title')),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: headCtrl,
                          style: const TextStyle(
                              color: AppTheme.textPrimary, fontSize: 13),
                          decoration: _inputDecoration('From branch')
                              .copyWith(labelText: 'From branch'))),
                  const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.arrow_forward,
                          color: AppTheme.textTertiary, size: 18)),
                  Expanded(
                      child: TextField(
                          controller: baseCtrl,
                          style: const TextStyle(
                              color: AppTheme.textPrimary, fontSize: 13),
                          decoration: _inputDecoration('To branch')
                              .copyWith(labelText: 'To branch'))),
                ]),
                const SizedBox(height: 12),
                TextField(
                    controller: bodyCtrl,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    maxLines: 3,
                    decoration: _inputDecoration('Description')
                        .copyWith(labelText: 'Description')),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: draft,
                  onChanged: (v) => setSt(() => draft = v),
                  title: const Text('Draft PR',
                      style: TextStyle(
                          fontSize: 14, color: AppTheme.textPrimary)),
                  subtitle: const Text(
                      'Cannot be merged until marked ready',
                      style: TextStyle(
                          fontSize: 12, color: AppTheme.textTertiary)),
                  activeColor: AppTheme.primary,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
                const SizedBox(height: 16),
                SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final t = titleCtrl.text.trim();
                        final h = headCtrl.text.trim();
                        final b = baseCtrl.text.trim();
                        if (t.isEmpty || h.isEmpty || b.isEmpty) return;
                        final p = repoName.split('/');
                        Navigator.pop(ctx);
                        try {
                          await _svc.createPullRequest(p[0], p[1], t, h, b,
                              body: bodyCtrl.text.trim(), draft: draft);
                          _toast('Pull request created');
                          if (_tabCtrl.index == 2) await _loadPRs();
                        } catch (e) {
                          _toast('Failed: \$e', isError: true);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10))),
                      child: const Text('Create Pull Request',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    )),
              ]),
        ),
      ),
    );
  }

  void _cloneSheet(GitHubRepo repo) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child:
            Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sheetHandle(),
          const SizedBox(height: 20),
          const Text('Clone Repository',
              style: TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary)),
          const SizedBox(height: 16),
          if (repo.cloneUrl != null) ...[
            _cloneUrlTile('HTTPS', repo.cloneUrl!),
            const SizedBox(height: 8)
          ],
          if (repo.sshUrl != null) _cloneUrlTile('SSH', repo.sshUrl!),
          const SizedBox(height: 8),
          if (repo.htmlUrl != null) _cloneUrlTile('GitHub', repo.htmlUrl!),
          const SizedBox(height: 12),
          Text('Clone locally to edit files, commit changes, and push.',
              style: TextStyle(
                  fontSize: 12, color: AppTheme.textTertiary.withOpacity(0.7))),
        ]),
      ),
    );
  }

  Widget _cloneUrlTile(String label, String url) => InkWell(
        onTap: () {
          Clipboard.setData(ClipboardData(text: url));
          _toast('URL copied');
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: AppTheme.surfaceInput,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border)),
            child: Row(children: [
              Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(label,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primary))),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(url,
                      style: const TextStyle(
                          fontFamily: AppTheme.fontCode,
                          fontSize: 12,
                          color: AppTheme.textSecondary),
                      overflow: TextOverflow.ellipsis)),
              const Icon(Icons.copy, size: 16, color: AppTheme.textTertiary),
            ])),
      );

  void _issueDetailSheet(dynamic issue) {
    // Legacy bottom sheet for quick preview; use GitHubIssueDetailScreen for full view
    final open = issue['state'] == 'open';
    final title = issue['title'] as String? ?? 'Untitled';
    final body = issue['body'] as String? ?? 'No description provided.';
    final num = issue['number'] as int? ?? 0;
    final labels = (issue['labels'] as List<dynamic>?) ?? [];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (ctx, sc) => Container(
                decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20))),
                child: Column(children: [
                  Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          border:
                              Border(bottom: BorderSide(color: AppTheme.divider))),
                      child: Row(children: [
                        Expanded(
                            child: Text('#$num: $title',
                                style: const TextStyle(
                                    fontFamily: AppTheme.fontBody,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textPrimary))),
                        IconButton(
                            onPressed: () => _navigateToIssueDetail(issue),
                            icon: const Icon(Icons.open_in_full,
                                color: AppTheme.accent, size: 20)),
                        IconButton(
                            onPressed: () async {
                              if (_repos.isEmpty) return;
                              try {
                                final ns = open ? 'closed' : 'open';
                                await _svc.updateIssue(_repos.first.owner,
                                    _repos.first.name, num,
                                    state: ns);
                                Navigator.pop(ctx);
                                _toast('Issue ${open ? 'closed' : 'reopened'}');
                                await _loadIssues();
                              } catch (e) {
                                _toast('Failed: \$e', isError: true);
                              }
                            },
                            icon: Icon(open ? Icons.check_circle : Icons.replay,
                                color:
                                    open ? AppTheme.success : AppTheme.accent)),
                        IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close,
                                color: AppTheme.textTertiary)),
                      ])),
                  Expanded(
                      child: SingleChildScrollView(
                          controller: sc,
                          padding: const EdgeInsets.all(16),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                        color: (open
                                                ? AppTheme.success
                                                : AppTheme.textTertiary)
                                            .withOpacity(0.15),
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    child: Text(open ? 'OPEN' : 'CLOSED',
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: open
                                                ? AppTheme.success
                                                : AppTheme.textTertiary,
                                            letterSpacing: 0.5))),
                                if (labels.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: labels.map<Widget>((l) {
                                        final name = l['name'] as String? ?? '';
                                        final c = _hexColor(
                                            l['color'] as String? ??
                                                '666666');
                                        return Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                                color: c.withOpacity(0.15),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                border: Border.all(
                                                    color: c.withOpacity(0.3),
                                                    width: 0.5)),
                                            child: Text(name,
                                                style: TextStyle(
                                                    fontSize: 10,
                                                    color: c,
                                                    fontWeight:
                                                        FontWeight.w500)));
                                      }).toList()),
                                ],
                                const SizedBox(height: 16),
                                Text(body,
                                    style: const TextStyle(
                                        fontFamily: AppTheme.fontBody,
                                        fontSize: 14,
                                        color: AppTheme.textSecondary,
                                        height: 1.6)),
                              ]))),
                ]),
              )),
    );
  }

  void _prDetailSheet(dynamic pr) {
    final title = pr['title'] as String? ?? 'Untitled';
    final body = pr['body'] as String? ?? '';
    final num = pr['number'] as int? ?? 0;
    final merged = pr['merged'] == true;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (ctx, sc) => Container(
                decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20))),
                child: Column(children: [
                  Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          border:
                              Border(bottom: BorderSide(color: AppTheme.divider))),
                      child: Row(children: [
                        Expanded(
                            child: Text('#$num: $title',
                                style: const TextStyle(
                                    fontFamily: AppTheme.fontBody,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textPrimary))),
                        ElevatedButton.icon(
                            onPressed: () => _navigateToPRReview(pr),
                            icon: const Icon(Icons.rate_review, size: 16),
                            label: const Text('Review'),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                                textStyle: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600))),
                        const SizedBox(width: 8),
                        if (!merged && pr['state'] == 'open')
                          ElevatedButton.icon(
                              onPressed: () => _mergeDialog(pr),
                              icon: const Icon(Icons.merge_type, size: 16),
                              label: const Text('Merge'),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.accent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                  textStyle: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600))),
                        const SizedBox(width: 8),
                        IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close,
                                color: AppTheme.textTertiary, size: 20)),
                      ])),
                  Expanded(
                      child: SingleChildScrollView(
                          controller: sc,
                          padding: const EdgeInsets.all(16),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (body.isNotEmpty)
                                  Text(body,
                                      style: const TextStyle(
                                          fontFamily: AppTheme.fontBody,
                                          fontSize: 14,
                                          color: AppTheme.textSecondary,
                                          height: 1.6)),
                                if (body.isNotEmpty)
                                  const SizedBox(height: 16),
                                const Text('Review Actions',
                                    style: TextStyle(
                                        fontFamily: AppTheme.fontBody,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.textPrimary)),
                                const SizedBox(height: 12),
                                Row(children: [
                                  _reviewBtn(Icons.check_circle, 'Approve',
                                      AppTheme.success, () => _submitReview(pr, 'APPROVE')),
                                  const SizedBox(width: 8),
                                  _reviewBtn(
                                      Icons.cancel,
                                      'Request Changes',
                                      AppTheme.error,
                                      () => _submitReview(pr, 'REQUEST_CHANGES')),
                                  const SizedBox(width: 8),
                                  _reviewBtn(Icons.comment, 'Comment',
                                      AppTheme.info, () => _submitReview(pr, 'COMMENT')),
                                ]),
                              ]))),
                ]),
              )),
    );
  }

  void _mergeDialog(dynamic pr) {
    final num = pr['number'] as int? ?? 0;
    String method = 'merge';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Merge Pull Request',
            style: TextStyle(
                color: AppTheme.textPrimary, fontFamily: AppTheme.fontBody)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Choose merge method:',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
          const SizedBox(height: 12),
          StatefulBuilder(
              builder: (ctx, setSt) => Column(children: [
                    _mergeRadio('merge', 'Create a merge commit', method,
                        (v) => setSt(() => method = v)),
                    _mergeRadio('squash', 'Squash and merge', method,
                        (v) => setSt(() => method = v)),
                    _mergeRadio('rebase', 'Rebase and merge', method,
                        (v) => setSt(() => method = v)),
                  ])),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: AppTheme.textTertiary))),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              if (_repos.isEmpty) return;
              try {
                await _svc.mergePullRequest(
                    _repos.first.owner, _repos.first.name, num,
                    method: method);
                _toast('PR merged');
                await _loadPRs();
              } catch (e) {
                _toast('Merge failed: \$e', isError: true);
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white),
            child: const Text('Merge'),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SHARED WIDGET BUILDERS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _empty(IconData icon, String title, String subtitle) => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 56, color: AppTheme.textTertiary.withOpacity(0.4)),
          const SizedBox(height: 16),
          Text(title,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary.withOpacity(0.7))),
          const SizedBox(height: 8),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, color: AppTheme.textTertiary.withOpacity(0.6))),
        ]),
      );

  Widget _filterChip(String value, String label, String selected,
          ValueChanged<String> onSelect) =>
      InkWell(
        onTap: () => onSelect(value),
        borderRadius: BorderRadius.circular(20),
        child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: selected == value
                  ? AppTheme.primary.withOpacity(0.2)
                  : AppTheme.surface.withOpacity(0.5),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: selected == value
                      ? AppTheme.primary.withOpacity(0.5)
                      : AppTheme.border,
                  width: 1),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected == value
                        ? FontWeight.w600
                        : FontWeight.w500,
                    color: selected == value
                        ? AppTheme.primary
                        : AppTheme.textSecondary))),
      );

  Widget _miniAction(IconData icon, String label, VoidCallback onTap) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 13, color: AppTheme.textTertiary),
              const SizedBox(width: 3),
              Text(label,
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textTertiary,
                      fontWeight: FontWeight.w500)),
            ])),
      );

  Widget _avatar(String name, {required Gradient gradient}) => Container(
      width: 20,
      height: 20,
      decoration:
          BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(6)),
      child: Center(
          child: Text(name[0].toUpperCase(),
              style: const TextStyle(
                  fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white))));

  Widget _reviewBtn(IconData icon, String label, Color color,
          VoidCallback onTap) =>
      Expanded(
        child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: color.withOpacity(0.3))),
                child: Column(children: [
                  Icon(icon, size: 22, color: color),
                  const SizedBox(height: 4),
                  Text(label,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: color))
                ]))),
      );

  Widget _mergeRadio(
          String val, String label, String sel, ValueChanged<String> onCh) =>
      RadioListTile<String>(
          value: val,
          groupValue: sel,
          onChanged: (v) => onCh(v!),
          title: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  color: sel == val ? AppTheme.textPrimary : AppTheme.textSecondary)),
          activeColor: AppTheme.primary,
          dense: true,
          contentPadding: EdgeInsets.zero);

  Widget _sheetHandle() => Center(
      child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
              color: AppTheme.border, borderRadius: BorderRadius.circular(2))));

  InputDecoration _inputDecoration(String hint, {IconData? icon, Widget? suffix}) =>
      InputDecoration(
          filled: true,
          fillColor: AppTheme.surfaceInput,
          hintText: hint,
          hintStyle: const TextStyle(color: AppTheme.textTertiary),
          prefixIcon: icon != null
              ? Icon(icon, color: AppTheme.textTertiary, size: 18)
              : null,
          suffixIcon: suffix,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.border)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
          labelStyle: const TextStyle(color: AppTheme.textSecondary),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14));

  String _ago(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inDays > 365) return '${diff.inDays ~/ 365}y ago';
    if (diff.inDays > 30) return '${diff.inDays ~/ 30}mo ago';
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'just now';
  }

  Color _hexColor(String hex) {
    final b = StringBuffer();
    if (hex.length == 6) b.write('FF');
    b.write(hex);
    return Color(int.parse(b.toString(), radix: 16));
  }
}
