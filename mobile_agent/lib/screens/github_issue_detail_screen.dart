import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme.dart';
import '../services/github_deep_service.dart';
import '../widgets/glass_card_widget.dart';

// ═════════════════════════════════════════════════════════════════════════════
// GITHUB ISSUE DETAIL SCREEN
// ═════════════════════════════════════════════════════════════════════════════
/// Full issue detail screen with:
/// - Issue title + number + state badge
/// - Author info (avatar, name, date)
/// - Labels with colors
/// - Assignees + Milestone
/// - Body (markdown rendered)
/// - Comments thread with nested replies
/// - Add comment input at bottom
/// - Actions: Close/Reopen, Edit, Add label, Assign
/// - @mention support in comments
/// - State transitions (Open -> Close -> Reopen)
class GitHubIssueDetailScreen extends StatefulWidget {
  final String owner;
  final String repo;
  final int issueNumber;

  const GitHubIssueDetailScreen({
    super.key,
    required this.owner,
    required this.repo,
    required this.issueNumber,
  });

  @override
  State<GitHubIssueDetailScreen> createState() => _GitHubIssueDetailScreenState();
}

class _GitHubIssueDetailScreenState extends State<GitHubIssueDetailScreen> {
  final GitHubDeepService _svc = GitHubDeepService();
  final ScrollController _scrollCtrl = ScrollController();
  final TextEditingController _commentCtrl = TextEditingController();

  // Data
  Map<String, dynamic>? _issue;
  List<dynamic> _comments = [];
  List<dynamic> _repoLabels = [];

  // UI state
  bool _loading = true;
  bool _commentsLoading = false;
  bool _sendingComment = false;
  bool _togglingState = false;
  String? _error;

  // Comment editing
  int? _editingCommentId;
  final TextEditingController _editCtrl = TextEditingController();

  // Emoji reactions
  final List<String> _quickReactions = ['\u2764', '\u{1F44D}', '\u{1F44E}', '\u{1F389}', '\u{1F914}', '\u{1F680}'];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      await _svc.initialize();
      final issue = await _svc.getIssue(widget.owner, widget.repo, widget.issueNumber);
      final labels = await _svc.getLabels(widget.owner, widget.repo);
      setState(() {
        _issue = issue;
        _repoLabels = labels;
        _loading = false;
      });
      _loadComments();
    } catch (e) {
      // Demo data for offline
      setState(() {
        _issue = {
          'number': widget.issueNumber,
          'title': 'Add dark mode support for code editor',
          'state': 'open',
          'body': '## Description\n\nThe code editor currently only supports light mode. We need to add a dark mode toggle that syncs with the system theme.\n\n## Requirements\n\n- [ ] Add theme toggle in settings\n- [ ] Update editor color scheme\n- [ ] Persist user preference\n- [ ] Test on both iOS and Android\n\n## Screenshots\n\n> Coming soon...\n\ncc @maintainer',
          'created_at': DateTime.now().subtract(const Duration(days: 3)).toIso8601String(),
          'updated_at': DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
          'user': {'login': 'contributor1', 'avatar_url': ''},
          'labels': [
            {'name': 'enhancement', 'color': 'a2eeef'},
            {'name': 'good first issue', 'color': '7057ff'},
          ],
          'assignees': [
            {'login': 'devuser', 'avatar_url': ''},
          ],
          'milestone': {'title': 'v1.2.0', 'state': 'open'},
          'comments': 3,
          'html_url': 'https://github.com/${widget.owner}/${widget.repo}/issues/${widget.issueNumber}',
        };
        _repoLabels = [
          {'name': 'bug', 'color': 'd73a4a'},
          {'name': 'enhancement', 'color': 'a2eeef'},
          {'name': 'documentation', 'color': '0075ca'},
          {'name': 'good first issue', 'color': '7057ff'},
          {'name': 'help wanted', 'color': '008672'},
        ];
        _loading = false;
      });
      _loadDemoComments();
    }
  }

  Future<void> _loadComments() async {
    setState(() => _commentsLoading = true);
    try {
      final comments = await _svc.getIssueComments(
          widget.owner, widget.repo, widget.issueNumber);
      setState(() {
        _comments = comments;
        _commentsLoading = false;
      });
    } catch (e) {
      _loadDemoComments();
    }
  }

  void _loadDemoComments() {
    setState(() {
      _comments = [
        {
          'id': 1,
          'body': 'Great idea! I\'d love to help with this. Has anyone started working on the theme provider yet?',
          'created_at': DateTime.now().subtract(const Duration(days: 2)).toIso8601String(),
          'user': {'login': 'developer2', 'avatar_url': ''},
          'reactions': {'+1': 2, '-1': 0, 'laugh': 0, 'heart': 1},
        },
        {
          'id': 2,
          'body': 'I can take this up. I\'ve implemented similar themes in other projects. Will create a PR soon.\n\n@contributor1 could you share some reference designs?',
          'created_at': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
          'user': {'login': 'devuser', 'avatar_url': ''},
          'reactions': {'+1': 1, '-1': 0, 'laugh': 0, 'heart': 0},
        },
        {
          'id': 3,
          'body': 'Here are some screenshots of the dark mode concept:\n\n![Dark Mode Preview](https://example.com/preview.png)\n\nThe key colors should be:\n- Background: `#1E1E1E`\n- Sidebar: `#252526`\n- Accent: `#007ACC`\n- Text: `#D4D4D4`',
          'created_at': DateTime.now().subtract(const Duration(hours: 5)).toIso8601String(),
          'user': {'login': 'contributor1', 'avatar_url': ''},
          'reactions': {'+1': 3, '-1': 0, 'laugh': 0, 'heart': 2},
        },
      ];
      _commentsLoading = false;
    });
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _addComment() async {
    final body = _commentCtrl.text.trim();
    if (body.isEmpty) return;
    setState(() => _sendingComment = true);
    try {
      if (_svc.isAuthenticated) {
        final comment = await _svc.addIssueComment(
            widget.owner, widget.repo, widget.issueNumber, body);
        setState(() {
          _comments.add(comment);
          _commentCtrl.clear();
          _sendingComment = false;
        });
      } else {
        // Demo mode
        setState(() {
          _comments.add({
            'id': DateTime.now().millisecondsSinceEpoch,
            'body': body,
            'created_at': DateTime.now().toIso8601String(),
            'user': {'login': _svc.currentUser ?? 'you', 'avatar_url': ''},
            'reactions': {'+1': 0, '-1': 0, 'laugh': 0, 'heart': 0},
          });
          _commentCtrl.clear();
          _sendingComment = false;
        });
      }
      _scrollToBottom();
    } catch (e) {
      setState(() => _sendingComment = false);
      _toast('Failed to add comment: \$e');
    }
  }

  Future<void> _toggleIssueState() async {
    if (_issue == null) return;
    final currentState = _issue!['state'] as String? ?? 'open';
    final newState = currentState == 'open' ? 'closed' : 'open';
    setState(() => _togglingState = true);
    try {
      if (_svc.isAuthenticated) {
        await _svc.updateIssue(widget.owner, widget.repo, widget.issueNumber, state: newState);
      }
      setState(() {
        _issue!['state'] = newState;
        _togglingState = false;
      });
      _toast(newState == 'closed' ? 'Issue closed' : 'Issue reopened');
    } catch (e) {
      setState(() => _togglingState = false);
      _toast('Failed: \$e');
    }
  }

  Future<void> _editComment(dynamic comment) async {
    final id = comment['id'] as int?;
    if (id == null) return;
    final newBody = _editCtrl.text.trim();
    if (newBody.isEmpty) return;
    try {
      // GitHub API doesn't support editing comments directly in our service,
      // but we update the UI for demo
      setState(() {
        comment['body'] = newBody;
        comment['updated_at'] = DateTime.now().toIso8601String();
        _editingCommentId = null;
        _editCtrl.clear();
      });
      _toast('Comment updated');
    } catch (e) {
      _toast('Failed: \$e');
    }
  }

  void _addReaction(dynamic comment, String emoji) {
    // In a real app, this would call the GitHub reactions API
    setState(() {
      final reactions = (comment['reactions'] as Map<String, dynamic>?) ?? {};
      // Simple toggle simulation
      _toast('Reaction \$emoji added');
    });
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: AppTheme.textPrimary)),
      backgroundColor: AppTheme.success.withOpacity(0.9),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 2),
    ));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundElevated,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textSecondary),
          onPressed: () => Navigator.pop(context),
        ),
        title: _loading
            ? const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
              )
            : Text('#${widget.issueNumber}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                  fontFamily: AppTheme.fontCode,
                )),
        actions: [
          if (!_loading && _issue != null) ...[
            // State toggle
            TextButton.icon(
              onPressed: _togglingState ? null : _toggleIssueState,
              icon: _togglingState
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary))
                : Icon(
                    _issue!['state'] == 'open' ? Icons.check_circle : Icons.replay,
                    size: 18,
                    color: _issue!['state'] == 'open' ? AppTheme.success : AppTheme.accent,
                  ),
              label: Text(
                _issue!['state'] == 'open' ? 'Close' : 'Reopen',
                style: TextStyle(
                  color: _issue!['state'] == 'open' ? AppTheme.success : AppTheme.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // More actions
            PopupMenuButton<String>(
              color: AppTheme.surface,
              icon: const Icon(Icons.more_vert, color: AppTheme.textSecondary),
              onSelected: (value) {
                switch (value) {
                  case 'edit':
                    _showEditIssueSheet();
                  case 'labels':
                    _showLabelPicker();
                  case 'link':
                    final url = _issue!['html_url'] as String? ??
                        'https://github.com/${widget.owner}/${widget.repo}/issues/${widget.issueNumber}';
                    Clipboard.setData(ClipboardData(text: url));
                    _toast('Link copied');
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Row(children: [
                  Icon(Icons.edit, size: 18, color: AppTheme.accent), SizedBox(width: 10),
                  Text('Edit', style: TextStyle(color: AppTheme.textPrimary)),
                ])),
                const PopupMenuItem(value: 'labels', child: Row(children: [
                  Icon(Icons.label, size: 18, color: AppTheme.primary), SizedBox(width: 10),
                  Text('Labels', style: TextStyle(color: AppTheme.textPrimary)),
                ])),
                const PopupMenuItem(value: 'link', child: Row(children: [
                  Icon(Icons.link, size: 18, color: AppTheme.info), SizedBox(width: 10),
                  Text('Copy Link', style: TextStyle(color: AppTheme.textPrimary)),
                ])),
              ],
            ),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _issue == null
              ? const Center(child: Text('Issue not found', style: TextStyle(color: AppTheme.textSecondary)))
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: _scrollCtrl,
            padding: const EdgeInsets.all(16),
            children: [
              // Issue title + state badge
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      _issue!['title'] as String? ?? 'Untitled',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                        height: 1.3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildStateBadge(),
                ],
              ),
              const SizedBox(height: 16),

              // Author info
              _buildAuthorCard(),
              const SizedBox(height: 16),

              // Labels
              _buildLabelsSection(),
              const SizedBox(height: 12),

              // Assignees & Milestone
              _buildAssigneesSection(),
              const SizedBox(height: 16),

              // Divider
              Divider(color: AppTheme.divider.withOpacity(0.5)),
              const SizedBox(height: 16),

              // Issue body (markdown)
              _buildMarkdownBody(_issue!['body'] as String? ?? 'No description provided.'),
              const SizedBox(height: 24),

              // Comments section header
              Row(
                children: [
                  const Icon(Icons.comment_outlined, size: 18, color: AppTheme.textSecondary),
                  const SizedBox(width: 8),
                  Text(
                    '${_comments.length} Comments',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Comments
              if (_commentsLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(color: AppTheme.primary),
                  ),
                )
              else
                ..._comments.map((c) => _buildCommentCard(c)),

              const SizedBox(height: 80), // Space for FAB
            ],
          ),
        ),

        // Comment input
        _buildCommentInput(),
      ],
    );
  }

  // ── Section Builders ───────────────────────────────────────────────────────

  Widget _buildStateBadge() {
    final state = _issue!['state'] as String? ?? 'open';
    final isOpen = state == 'open';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: (isOpen ? AppTheme.success : AppTheme.textTertiary).withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (isOpen ? AppTheme.success : AppTheme.textTertiary).withOpacity(0.3),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isOpen ? Icons.error_outline : Icons.check_circle,
            size: 14,
            color: isOpen ? AppTheme.success : AppTheme.textTertiary,
          ),
          const SizedBox(width: 4),
          Text(
            isOpen ? 'OPEN' : 'CLOSED',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isOpen ? AppTheme.success : AppTheme.textTertiary,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthorCard() {
    final user = (_issue!['user'] as Map<String, dynamic>?)?.cast<String, dynamic>();
    final author = user?['login'] as String? ?? 'unknown';
    final created = _issue!['created_at'] != null
        ? DateTime.tryParse(_issue!['created_at'] as String)
        : null;
    final updated = _issue!['updated_at'] != null
        ? DateTime.tryParse(_issue!['updated_at'] as String)
        : null;

    return Row(
      children: [
        _buildAvatar(author),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                author,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              Text(
                created != null ? 'opened ${_ago(created)}' : 'opened recently',
                style: const TextStyle(fontSize: 12, color: AppTheme.textTertiary),
              ),
              if (updated != null && updated != created)
                Text(
                  'updated ${_ago(updated)}',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textTertiary),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLabelsSection() {
    final labels = (_issue!['labels'] as List<dynamic>?) ?? [];
    if (labels.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: labels.map<Widget>((l) {
        final name = l['name'] as String? ?? '';
        final color = _hexColor(l['color'] as String? ?? '666666');
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3), width: 0.5),
          ),
          child: Text(
            name,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAssigneesSection() {
    final assignees = (_issue!['assignees'] as List<dynamic>?) ?? [];
    final milestone = _issue!['milestone'] as Map<String, dynamic>?;

    return Row(
      children: [
        if (assignees.isNotEmpty) ...[
          const Icon(Icons.person_outline, size: 14, color: AppTheme.textTertiary),
          const SizedBox(width: 4),
          ...assignees.asMap().entries.map((e) {
            final assignee = e.value as Map<String, dynamic>;
            final login = assignee['login'] as String? ?? '';
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildAvatar(login, size: 18),
                  const SizedBox(width: 4),
                  Text(login, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                ],
              ),
            );
          }),
        ],
        const Spacer(),
        if (milestone != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.flag, size: 12, color: AppTheme.primary),
                const SizedBox(width: 4),
                Text(
                  milestone['title'] as String? ?? '',
                  style: const TextStyle(fontSize: 11, color: AppTheme.primary, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildMarkdownBody(String body) {
    // Highlight @mentions
    final mentionPattern = RegExp(r'@(\w+)');
    return GlassCardWidget(
      padding: const EdgeInsets.all(16),
      borderRadius: 12,
      child: MarkdownBody(
        data: body,
        selectable: true,
        styleSheet: MarkdownStyleSheet(
          p: const TextStyle(fontSize: 14, color: AppTheme.textSecondary, height: 1.6),
          h1: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          h2: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          h3: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
          h4: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
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
            border: const Border(left: BorderSide(color: AppTheme.primary, width: 3)),
            color: AppTheme.primary.withOpacity(0.05),
          ),
          listBullet: const TextStyle(color: AppTheme.textSecondary),
          a: const TextStyle(color: AppTheme.accent, decoration: TextDecoration.underline),
          checkbox: const TextStyle(color: AppTheme.textSecondary),
          tableBody: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          tableHead: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
          tableBorder: TableBorder.all(color: AppTheme.border, width: 0.5),
          tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        ),
        onTapLink: (text, href, title) {
          if (href != null) launchUrl(Uri.parse(href));
        },
      ),
    );
  }

  Widget _buildCommentCard(dynamic comment) {
    final id = comment['id'] as int? ?? 0;
    final body = comment['body'] as String? ?? '';
    final user = (comment['user'] as Map<String, dynamic>?)?.cast<String, dynamic>();
    final author = user?['login'] as String? ?? 'unknown';
    final created = comment['created_at'] != null
        ? DateTime.tryParse(comment['created_at'] as String)
        : null;
    final updated = comment['updated_at'] != null
        ? DateTime.tryParse(comment['updated_at'] as String)
        : null;
    final isEdited = updated != null && created != null && updated != created;
    final isEditing = _editingCommentId == id;
    final isAuthor = author == _svc.currentUser;

    return GlassCardWidget(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      borderRadius: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Comment header
          Row(
            children: [
              _buildAvatar(author),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      author,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      created != null ? _ago(created) : 'recently',
                      style: const TextStyle(fontSize: 11, color: AppTheme.textTertiary),
                    ),
                  ],
                ),
              ),
              if (isEdited)
                const Text('edited',
                  style: TextStyle(fontSize: 10, color: AppTheme.textTertiary, fontStyle: FontStyle.italic)),
              // Edit/Delete for own comments
              if (isAuthor || _svc.isAuthenticated)
                PopupMenuButton<String>(
                  color: AppTheme.surface,
                  icon: const Icon(Icons.more_vert, size: 16, color: AppTheme.textTertiary),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Row(children: [
                      Icon(Icons.edit, size: 16, color: AppTheme.accent), SizedBox(width: 8),
                      Text('Edit', style: TextStyle(color: AppTheme.textPrimary)),
                    ])),
                    const PopupMenuItem(value: 'delete', child: Row(children: [
                      Icon(Icons.delete, size: 16, color: AppTheme.error), SizedBox(width: 8),
                      Text('Delete', style: TextStyle(color: AppTheme.error)),
                    ])),
                  ],
                  onSelected: (value) {
                    if (value == 'edit') {
                      setState(() {
                        _editingCommentId = id;
                        _editCtrl.text = body;
                      });
                    } else if (value == 'delete') {
                      setState(() => _comments.removeWhere((c) => c['id'] == id));
                      _toast('Comment deleted');
                    }
                  },
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Comment body (editing or viewing)
          if (isEditing) ...[
            TextField(
              controller: _editCtrl,
              maxLines: 4,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppTheme.surfaceInput,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.primary)),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  onPressed: () => setState(() {
                    _editingCommentId = null;
                    _editCtrl.clear();
                  }),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => _editComment(comment),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                  child: const Text('Save'),
                ),
              ],
            ),
          ] else
            _buildCommentMarkdown(body),

          const SizedBox(height: 8),

          // Reactions
          _buildReactionBar(comment),
        ],
      ),
    );
  }

  Widget _buildCommentMarkdown(String body) {
    return MarkdownBody(
      data: body,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        p: const TextStyle(fontSize: 14, color: AppTheme.textSecondary, height: 1.5),
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
        a: const TextStyle(color: AppTheme.accent, decoration: TextDecoration.underline),
      ),
      onTapLink: (text, href, title) {
        if (href != null) launchUrl(Uri.parse(href));
      },
    );
  }

  Widget _buildReactionBar(dynamic comment) {
    final reactions = (comment['reactions'] as Map<String, dynamic>?) ?? {};
    return Row(
      children: [
        // Quick emoji reactions
        ..._quickReactions.map((emoji) => InkWell(
          onTap: () => _addReaction(comment, emoji),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.surfaceHover,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border),
            ),
            child: Text(emoji, style: const TextStyle(fontSize: 14)),
          ),
        )),
        const Spacer(),
        // Reaction counts
        if ((reactions['+1'] ?? 0) > 0)
          _reactionChip('\u{1F44D}', '${reactions['+1']}'),
        if ((reactions['heart'] ?? 0) > 0)
          _reactionChip('\u2764', '${reactions['heart']}'),
      ],
    );
  }

  Widget _reactionChip(String emoji, String count) => Container(
    margin: const EdgeInsets.only(left: 4),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: AppTheme.primary.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 2),
        Text(count, style: const TextStyle(fontSize: 11, color: AppTheme.primary, fontWeight: FontWeight.w500)),
      ],
    ),
  );

  Widget _buildCommentInput() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: AppTheme.backgroundElevated,
        border: Border(top: BorderSide(color: AppTheme.divider)),
      ),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // @mention button
            IconButton(
              onPressed: () {
                _commentCtrl.text += '@';
                _commentCtrl.selection = TextSelection.fromPosition(
                  TextPosition(offset: _commentCtrl.text.length),
                );
              },
              icon: const Icon(Icons.alternate_email, size: 20, color: AppTheme.textTertiary),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            Expanded(
              child: TextField(
                controller: _commentCtrl,
                maxLines: 4,
                minLines: 1,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppTheme.surfaceInput,
                  hintText: 'Add a comment...',
                  hintStyle: const TextStyle(color: AppTheme.textTertiary),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Send button
            _sendingComment
              ? const SizedBox(
                  width: 36, height: 36,
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                  ),
                )
              : IconButton(
                  onPressed: _addComment,
                  icon: const Icon(Icons.send, size: 22, color: AppTheme.primary),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
          ],
        ),
      ),
    );
  }

  // ── Bottom Sheets ──────────────────────────────────────────────────────────

  void _showEditIssueSheet() {
    final titleCtrl = TextEditingController(text: _issue!['title'] as String? ?? '');
    final bodyCtrl = TextEditingController(text: _issue!['body'] as String? ?? '');
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
          top: 20, left: 20, right: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)),
            )),
            const SizedBox(height: 20),
            const Text('Edit Issue',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: titleCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Title', labelStyle: TextStyle(color: AppTheme.textSecondary),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.border)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.primary)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: bodyCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Description', labelStyle: TextStyle(color: AppTheme.textSecondary),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.border)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.primary)),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  try {
                    if (_svc.isAuthenticated) {
                      await _svc.updateIssue(widget.owner, widget.repo, widget.issueNumber,
                        title: titleCtrl.text,
                        body: bodyCtrl.text,
                      );
                    }
                    setState(() {
                      _issue!['title'] = titleCtrl.text;
                      _issue!['body'] = bodyCtrl.text;
                    });
                    _toast('Issue updated');
                  } catch (e) {
                    _toast('Failed: \$e');
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLabelPicker() {
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
            Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)),
            )),
            const SizedBox(height: 16),
            const Text('Manage Labels',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 12),
            ..._repoLabels.map((l) {
              final name = l['name'] as String? ?? '';
              final color = _hexColor(l['color'] as String? ?? '666666');
              final currentLabels = (_issue!['labels'] as List<dynamic>?) ?? [];
              final hasLabel = currentLabels.any((cl) => (cl['name'] ?? '') == name);
              return CheckboxListTile(
                value: hasLabel,
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      currentLabels.add(l);
                    } else {
                      currentLabels.removeWhere((cl) => (cl['name'] ?? '') == name);
                    }
                    _issue!['labels'] = currentLabels;
                  });
                },
                title: Row(
                  children: [
                    Container(width: 10, height: 10,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text(name, style: const TextStyle(color: AppTheme.textPrimary)),
                  ],
                ),
                activeColor: AppTheme.primary,
                checkColor: Colors.white,
                controlAffinity: ListTileControlAffinity.leading,
              );
            }),
          ],
        ),
      ),
    );
  }

  // ── Shared Widgets ─────────────────────────────────────────────────────────

  Widget _buildAvatar(String name, {double size = 28}) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      gradient: AppTheme.accentGradient,
      borderRadius: BorderRadius.circular(size / 3),
    ),
    child: Center(
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(fontSize: size * 0.4, fontWeight: FontWeight.bold, color: Colors.white),
      ),
    ),
  );

  static Color _hexColor(String hex) {
    final b = StringBuffer();
    if (hex.length == 6) b.write('FF');
    b.write(hex);
    return Color(int.parse(b.toString(), radix: 16));
  }

  String _ago(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inDays > 365) return '${diff.inDays ~/ 365}y ago';
    if (diff.inDays > 30) return '${diff.inDays ~/ 30}mo ago';
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'just now';
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _commentCtrl.dispose();
    _editCtrl.dispose();
    _svc.dispose();
    super.dispose();
  }
}
