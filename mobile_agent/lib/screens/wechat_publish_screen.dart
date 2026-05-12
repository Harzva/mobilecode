// lib/screens/wechat_publish_screen.dart
// WeChat Publish Screen — UI for publishing articles to WeChat Official Account.
//
// Features:
// - Login section (AppID/AppSecret input + authenticate)
// - Article editor (title + markdown editor)
// - Image upload for cover
// - Preview button
// - Draft list
// - Published articles list
// - Stats display (reads/likes)
// - Settings (comment toggle, fan-only toggle)
//
// Design: Dark theme, editor with preview split view.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../services/wechat_publish_service.dart';
import '../widgets/glass_card_widget.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Provider
// ═══════════════════════════════════════════════════════════════════════════

/// Provider for the WeChat publish service instance.
final wechatPublishServiceProvider = Provider<WeChatPublishService>((ref) {
  throw UnimplementedError('Override this provider with a real instance');
});

/// Tab index for the publish screen (0 = editor, 1 = drafts, 2 = published).
final wechatTabProvider = StateProvider<int>((ref) => 0);

/// Authentication state for WeChat.
final wechatAuthProvider = StateProvider<bool>((ref) => false);

/// Loading state for async operations.
final wechatLoadingProvider = StateProvider<bool>((ref) => false);

/// Error message provider.
final wechatErrorProvider = StateProvider<String?>((ref) => null);

/// Drafts list provider.
final wechatDraftsProvider = StateProvider<List<WeChatDraft>>((ref) => []);

/// Published articles provider.
final wechatPublishedProvider = StateProvider<List<WeChatArticle>>((ref) => []);

/// Selected draft/article for editing.
final wechatSelectedItemProvider = StateProvider<WeChatDraft?>((ref) => null);

// ═══════════════════════════════════════════════════════════════════════════
// Screen
// ═══════════════════════════════════════════════════════════════════════════

/// WeChat Publish Screen
///
/// Full-featured screen for composing and publishing WeChat articles.
/// Includes authentication, editor, draft management, and publishing.
class WeChatPublishScreen extends ConsumerStatefulWidget {
  const WeChatPublishScreen({super.key});

  @override
  ConsumerState<WeChatPublishScreen> createState() => _WeChatPublishScreenState();
}

class _WeChatPublishScreenState extends ConsumerState<WeChatPublishScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) {
      ref.read(wechatTabProvider.notifier).state = _tabController.index;
      ref.read(wechatErrorProvider.notifier).state = null;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAuthenticated = ref.watch(wechatAuthProvider);
    final isLoading = ref.watch(wechatLoadingProvider);
    final error = ref.watch(wechatErrorProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundElevated,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
        title: const Text('WeChat Publish'),
        bottom: isAuthenticated
            ? TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(icon: Icon(Icons.edit_note), text: 'Editor'),
                  Tab(icon: Icon(Icons.drafts_outlined), text: 'Drafts'),
                  Tab(icon: Icon(Icons.publish_outlined), text: 'Published'),
                ],
              )
            : null,
        actions: [
          if (isAuthenticated)
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Logout',
              onPressed: () => _logout(ref),
            ),
        ],
      ),
      body: isLoading
          ? const _LoadingOverlay()
          : isAuthenticated
              ? TabBarView(
                  controller: _tabController,
                  children: const [
                    _EditorTab(),
                    _DraftsTab(),
                    _PublishedTab(),
                  ],
                )
              : _LoginPanel(onLogin: () => _checkAuth(ref)),
    );
  }

  Future<void> _checkAuth(WidgetRef ref) async {
    final service = ref.read(wechatPublishServiceProvider);
    final success = await service.restoreAuthentication();
    if (success) {
      ref.read(wechatAuthProvider.notifier).state = true;
    }
  }

  Future<void> _logout(WidgetRef ref) async {
    final service = ref.read(wechatPublishServiceProvider);
    await service.logout();
    ref.read(wechatAuthProvider.notifier).state = false;
    ref.read(wechatDraftsProvider.notifier).state = [];
    ref.read(wechatPublishedProvider.notifier).state = [];
    ref.read(wechatSelectedItemProvider.notifier).state = null;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Login Panel
// ═══════════════════════════════════════════════════════════════════════════

class _LoginPanel extends ConsumerStatefulWidget {
  final VoidCallback onLogin;

  const _LoginPanel({required this.onLogin});

  @override
  ConsumerState<_LoginPanel> createState() => _LoginPanelState();
}

class _LoginPanelState extends ConsumerState<_LoginPanel> {
  final _appIdController = TextEditingController();
  final _appSecretController = TextEditingController();
  bool _obscureSecret = true;
  bool _isAuthenticating = false;

  @override
  void dispose() {
    _appIdController.dispose();
    _appSecretController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: GlassCard(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Icon
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.chat_bubble_outline,
                      color: AppTheme.textOnPrimary,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Title
                  Text(
                    'WeChat Official Account',
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Connect to publish articles to your 微信公众号',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // AppID input
                  TextField(
                    controller: _appIdController,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'AppID',
                      hintText: 'wx...',
                      prefixIcon: const Icon(Icons.app_registration, color: AppTheme.textSecondary),
                      filled: true,
                      fillColor: AppTheme.surfaceInput,
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
                  const SizedBox(height: 16),

                  // AppSecret input
                  TextField(
                    controller: _appSecretController,
                    obscureText: _obscureSecret,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'AppSecret',
                      hintText: 'Your app secret',
                      prefixIcon: const Icon(Icons.key_outlined, color: AppTheme.textSecondary),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureSecret ? Icons.visibility_off : Icons.visibility,
                          color: AppTheme.textSecondary,
                        ),
                        onPressed: () => setState(() => _obscureSecret = !_obscureSecret),
                      ),
                      filled: true,
                      fillColor: AppTheme.surfaceInput,
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
                  const SizedBox(height: 24),

                  // Authenticate button
                  ElevatedButton.icon(
                    onPressed: _isAuthenticating ? null : _authenticate,
                    icon: _isAuthenticating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.textOnPrimary),
                            ),
                          )
                        : const Icon(Icons.login),
                    label: Text(_isAuthenticating ? 'Authenticating...' : 'Connect'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: AppTheme.textOnPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Help text
                  TextButton.icon(
                    onPressed: _showHelpDialog,
                    icon: const Icon(Icons.help_outline, size: 16),
                    label: const Text('How to get AppID & AppSecret?'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _authenticate() async {
    final appId = _appIdController.text.trim();
    final appSecret = _appSecretController.text.trim();

    if (appId.isEmpty || appSecret.isEmpty) {
      ref.read(wechatErrorProvider.notifier).state = 'Please enter both AppID and AppSecret';
      return;
    }

    setState(() => _isAuthenticating = true);
    ref.read(wechatLoadingProvider.notifier).state = true;
    ref.read(wechatErrorProvider.notifier).state = null;

    try {
      final service = ref.read(wechatPublishServiceProvider);
      final success = await service.authenticate(appId, appSecret);

      if (success) {
        ref.read(wechatAuthProvider.notifier).state = true;
        widget.onLogin();
      } else {
        ref.read(wechatErrorProvider.notifier).state = 'Authentication failed. Please check your credentials.';
      }
    } catch (e) {
      ref.read(wechatErrorProvider.notifier).state = 'Error: $e';
    } finally {
      setState(() => _isAuthenticating = false);
      ref.read(wechatLoadingProvider.notifier).state = false;
    }
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Getting Started'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '1. Log in to WeChat Official Account Platform\n'
              '   (mp.weixin.qq.com)\n\n'
              '2. Go to "Development" > "Basic Configuration"\n\n'
              '3. Copy your AppID and AppSecret\n\n'
              '4. Make sure IP whitelist includes your server',
              style: TextStyle(color: AppTheme.textSecondary, height: 1.6),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Editor Tab
// ═══════════════════════════════════════════════════════════════════════════

class _EditorTab extends ConsumerStatefulWidget {
  const _EditorTab();

  @override
  ConsumerState<_EditorTab> createState() => _EditorTabState();
}

class _EditorTabState extends ConsumerState<_EditorTab> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _authorController = TextEditingController();
  final _digestController = TextEditingController();
  bool _showPreview = false;
  bool _openComments = false;
  bool _fansOnlyComments = false;

  @override
  void initState() {
    super.initState();
    // If editing an existing draft, load its content.
    final selected = ref.read(wechatSelectedItemProvider);
    if (selected != null) {
      _titleController.text = selected.title;
      _contentController.text = selected.content;
      _authorController.text = selected.author ?? '';
      _digestController.text = selected.digest ?? '';
      _openComments = selected.needOpenComment == 1;
      _fansOnlyComments = selected.onlyFansCanComment == 1;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _authorController.dispose();
    _digestController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Title row with action buttons
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _titleController,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Article title...',
                    hintStyle: TextStyle(color: AppTheme.textTertiary),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              // Preview toggle
              IconButton(
                icon: Icon(
                  _showPreview ? Icons.visibility_off : Icons.visibility,
                  color: AppTheme.textSecondary,
                ),
                tooltip: _showPreview ? 'Hide preview' : 'Show preview',
                onPressed: () => setState(() => _showPreview = !_showPreview),
              ),
              // Settings
              IconButton(
                icon: const Icon(Icons.settings_outlined, color: AppTheme.textSecondary),
                tooltip: 'Settings',
                onPressed: _showSettingsSheet,
              ),
            ],
          ),
          const Divider(color: AppTheme.divider),

          // Editor + optional preview
          Expanded(
            child: _showPreview
                ? Row(
                    children: [
                      Expanded(child: _buildEditor()),
                      const VerticalDivider(color: AppTheme.divider, width: 1),
                      Expanded(child: _buildPreview()),
                    ],
                  )
                : _buildEditor(),
          ),

          const Divider(color: AppTheme.divider),

          // Bottom action bar
          _buildActionBar(),
        ],
      ),
    );
  }

  Widget _buildEditor() {
    return Container(
      color: AppTheme.editorBackground,
      child: TextField(
        controller: _contentController,
        maxLines: null,
        expands: true,
        style: const TextStyle(
          color: AppTheme.textPrimary,
          fontFamily: AppTheme.fontCode,
          fontSize: 14,
          height: 1.6,
        ),
        decoration: const InputDecoration(
          hintText: 'Write your article content here...\n\n'
              'Supports HTML and Markdown.',
          hintStyle: TextStyle(
            color: AppTheme.textTertiary,
            fontFamily: AppTheme.fontCode,
            fontSize: 14,
          ),
          border: InputBorder.none,
          contentPadding: EdgeInsets.all(16),
        ),
      ),
    );
  }

  Widget _buildPreview() {
    return Container(
      color: AppTheme.background,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Preview header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primaryMuted,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'PREVIEW',
                  style: TextStyle(
                    color: AppTheme.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Title preview
          Text(
            _titleController.text.isEmpty ? 'Untitled Article' : _titleController.text,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),

          // Author
          if (_authorController.text.isNotEmpty)
            Text(
              'By ${_authorController.text}',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          const SizedBox(height: 16),

          // Content preview (simplified)
          Expanded(
            child: SingleChildScrollView(
              child: Text(
                _contentController.text.isEmpty
                    ? 'Start writing to see preview...'
                    : _contentController.text,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 14,
                  height: 1.6,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          // Save draft
          OutlinedButton.icon(
            onPressed: _saveDraft,
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('Save Draft'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.textSecondary,
              side: const BorderSide(color: AppTheme.border),
            ),
          ),
          const SizedBox(width: 8),

          // Upload cover image
          OutlinedButton.icon(
            onPressed: _uploadCover,
            icon: const Icon(Icons.image_outlined, size: 18),
            label: const Text('Cover'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.textSecondary,
              side: const BorderSide(color: AppTheme.border),
            ),
          ),
          const Spacer(),

          // Preview to WeChat
          OutlinedButton.icon(
            onPressed: _sendPreview,
            icon: const Icon(Icons.phone_android, size: 18),
            label: const Text('Preview'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.accent,
              side: const BorderSide(color: AppTheme.accent),
            ),
          ),
          const SizedBox(width: 8),

          // Publish
          ElevatedButton.icon(
            onPressed: _publishArticle,
            icon: const Icon(Icons.send, size: 18),
            label: const Text('Publish'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: AppTheme.textOnPrimary,
            ),
          ),
        ],
      ),
    );
  }

  void _showSettingsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Article Settings', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 20),

              // Author
              TextField(
                controller: _authorController,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Author',
                  hintText: 'Author name',
                  prefixIcon: Icon(Icons.person_outline, color: AppTheme.textSecondary),
                ),
              ),
              const SizedBox(height: 12),

              // Digest/Summary
              TextField(
                controller: _digestController,
                style: const TextStyle(color: AppTheme.textPrimary),
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Summary (Digest)',
                  hintText: 'Brief summary of the article (max 120 chars)',
                  prefixIcon: Icon(Icons.summarize_outlined, color: AppTheme.textSecondary),
                ),
              ),
              const SizedBox(height: 16),

              // Comment settings
              SwitchListTile(
                value: _openComments,
                onChanged: (v) => setLocalState(() => _openComments = v),
                title: const Text('Open Comments', style: TextStyle(color: AppTheme.textPrimary)),
                subtitle: const Text('Allow readers to comment',
                    style: TextStyle(color: AppTheme.textTertiary, fontSize: 12)),
                activeColor: AppTheme.primary,
              ),
              SwitchListTile(
                value: _fansOnlyComments,
                onChanged: _openComments
                    ? (v) => setLocalState(() => _fansOnlyComments = v)
                    : null,
                title: const Text('Fans Only Comments',
                    style: TextStyle(color: AppTheme.textPrimary)),
                subtitle: const Text('Only followers can comment',
                    style: TextStyle(color: AppTheme.textTertiary, fontSize: 12)),
                activeColor: AppTheme.primary,
              ),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: AppTheme.textOnPrimary,
                  ),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveDraft() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    if (title.isEmpty || content.isEmpty) {
      _showSnackBar('Please enter both title and content');
      return;
    }

    ref.read(wechatLoadingProvider.notifier).state = true;
    try {
      final service = ref.read(wechatPublishServiceProvider);
      final draft = await service.createDraft(
        title: title,
        content: content,
        author: _authorController.text.trim(),
        digest: _digestController.text.trim(),
        needOpenComment: _openComments ? 1 : 0,
        onlyFansCanComment: _fansOnlyComments ? 1 : 0,
      );

      // Update drafts list.
      final drafts = ref.read(wechatDraftsProvider);
      ref.read(wechatDraftsProvider.notifier).state = [...drafts, draft];

      _showSnackBar('Draft saved: ${draft.title}');
    } catch (e) {
      _showSnackBar('Failed to save draft: $e');
    } finally {
      ref.read(wechatLoadingProvider.notifier).state = false;
    }
  }

  Future<void> _uploadCover() async {
    _showSnackBar('Cover upload: Use image picker to select cover image');
    // In production, this would open an image picker and call service.uploadImage().
  }

  Future<void> _sendPreview() async {
    _showSnackBar('Preview: Enter OpenID to send preview to a WeChat user');
    // In production, this would show a dialog to enter OpenID and call service.preview().
  }

  Future<void> _publishArticle() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    if (title.isEmpty || content.isEmpty) {
      _showSnackBar('Please enter both title and content');
      return;
    }

    // Confirm publish.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Publish Article?'),
        content: Text('"$title" will be published to all subscribers.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            child: const Text('Publish'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    ref.read(wechatLoadingProvider.notifier).state = true;
    try {
      final service = ref.read(wechatPublishServiceProvider);

      // First create/update draft, then publish.
      final draft = await service.createDraft(
        title: title,
        content: content,
        author: _authorController.text.trim(),
        digest: _digestController.text.trim(),
        needOpenComment: _openComments ? 1 : 0,
        onlyFansCanComment: _fansOnlyComments ? 1 : 0,
      );

      final result = await service.publish(draft.mediaId);

      if (result.success) {
        _showSnackBar('Published successfully! ID: ${result.publishId}');
        _titleController.clear();
        _contentController.clear();
        _digestController.clear();
      } else {
        _showSnackBar('Publish failed: ${result.error}');
      }
    } catch (e) {
      _showSnackBar('Publish error: $e');
    } finally {
      ref.read(wechatLoadingProvider.notifier).state = false;
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.surfaceHover,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Drafts Tab
// ═══════════════════════════════════════════════════════════════════════════

class _DraftsTab extends ConsumerWidget {
  const _DraftsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drafts = ref.watch(wechatDraftsProvider);
    final isLoading = ref.watch(wechatLoadingProvider);

    if (isLoading && drafts.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    if (drafts.isEmpty) {
      return _EmptyState(
        icon: Icons.drafts_outlined,
        title: 'No Drafts',
        subtitle: 'Save drafts from the editor to see them here',
        action: TextButton.icon(
          onPressed: () {
            // Switch to editor tab.
            final tabController = DefaultTabController.of(context);
            tabController?.animateTo(0);
          },
          icon: const Icon(Icons.edit),
          label: const Text('Write a Draft'),
        ),
      );
    }

    return RefreshIndicator(
      color: AppTheme.primary,
      backgroundColor: AppTheme.surface,
      onRefresh: () => _loadDrafts(ref),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: drafts.length,
        itemBuilder: (context, index) {
          final draft = drafts[index];
          return _DraftCard(
            draft: draft,
            onEdit: () => _editDraft(ref, draft),
            onDelete: () => _deleteDraft(ref, draft),
            onPublish: () => _publishDraft(ref, draft),
          );
        },
      ),
    );
  }

  Future<void> _loadDrafts(WidgetRef ref) async {
    ref.read(wechatLoadingProvider.notifier).state = true;
    try {
      final service = ref.read(wechatPublishServiceProvider);
      final drafts = await service.getDrafts();
      ref.read(wechatDraftsProvider.notifier).state = drafts;
    } catch (e) {
      ref.read(wechatErrorProvider.notifier).state = 'Failed to load drafts: $e';
    } finally {
      ref.read(wechatLoadingProvider.notifier).state = false;
    }
  }

  void _editDraft(WidgetRef ref, WeChatDraft draft) {
    ref.read(wechatSelectedItemProvider.notifier).state = draft;
    // Switch to editor tab.
  }

  Future<void> _deleteDraft(WidgetRef ref, WeChatDraft draft) async {
    ref.read(wechatLoadingProvider.notifier).state = true;
    try {
      final service = ref.read(wechatPublishServiceProvider);
      await service.deleteDraft(draft.mediaId);
      final drafts = ref.read(wechatDraftsProvider).where((d) => d.mediaId != draft.mediaId).toList();
      ref.read(wechatDraftsProvider.notifier).state = drafts;
    } catch (e) {
      ref.read(wechatErrorProvider.notifier).state = 'Failed to delete: $e';
    } finally {
      ref.read(wechatLoadingProvider.notifier).state = false;
    }
  }

  Future<void> _publishDraft(WidgetRef ref, WeChatDraft draft) async {
    ref.read(wechatLoadingProvider.notifier).state = true;
    try {
      final service = ref.read(wechatPublishServiceProvider);
      final result = await service.publish(draft.mediaId);
      if (result.success) {
        // Remove from drafts.
        final drafts = ref.read(wechatDraftsProvider).where((d) => d.mediaId != draft.mediaId).toList();
        ref.read(wechatDraftsProvider.notifier).state = drafts;
      }
    } catch (e) {
      ref.read(wechatErrorProvider.notifier).state = 'Failed to publish: $e';
    } finally {
      ref.read(wechatLoadingProvider.notifier).state = false;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Published Tab
// ═══════════════════════════════════════════════════════════════════════════

class _PublishedTab extends ConsumerWidget {
  const _PublishedTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final articles = ref.watch(wechatPublishedProvider);

    if (articles.isEmpty) {
      return _EmptyState(
        icon: Icons.publish_outlined,
        title: 'No Published Articles',
        subtitle: 'Published articles will appear here',
        action: TextButton.icon(
          onPressed: () => _loadPublished(ref),
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh'),
        ),
      );
    }

    return RefreshIndicator(
      color: AppTheme.primary,
      backgroundColor: AppTheme.surface,
      onRefresh: () => _loadPublished(ref),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: articles.length,
        itemBuilder: (context, index) {
          final article = articles[index];
          return _PublishedCard(article: article);
        },
      ),
    );
  }

  Future<void> _loadPublished(WidgetRef ref) async {
    ref.read(wechatLoadingProvider.notifier).state = true;
    try {
      final service = ref.read(wechatPublishServiceProvider);
      final articles = await service.getPublishedArticles();
      ref.read(wechatPublishedProvider.notifier).state = articles;
    } catch (e) {
      ref.read(wechatErrorProvider.notifier).state = 'Failed to load: $e';
    } finally {
      ref.read(wechatLoadingProvider.notifier).state = false;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Shared Widgets
// ═══════════════════════════════════════════════════════════════════════════

class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.background.withOpacity(0.8),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppTheme.primary),
            SizedBox(height: 16),
            Text(
              'Processing...',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: AppTheme.textTertiary),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.textTertiary,
                ),
            textAlign: TextAlign.center,
          ),
          if (action != null) ...[
            const SizedBox(height: 16),
            action!,
          ],
        ],
      ),
    );
  }
}

class _DraftCard extends StatelessWidget {
  final WeChatDraft draft;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onPublish;

  const _DraftCard({
    required this.draft,
    this.onEdit,
    this.onDelete,
    this.onPublish,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppTheme.surface,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppTheme.border),
      ),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      draft.title.isEmpty ? 'Untitled' : draft.title,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Status chip
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.accentMuted,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'DRAFT',
                      style: TextStyle(
                        color: AppTheme.accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (draft.digest != null && draft.digest!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  draft.digest!,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 12, color: AppTheme.textTertiary),
                  const SizedBox(width: 4),
                  Text(
                    _formatDate(draft.updateTime),
                    style: const TextStyle(color: AppTheme.textTertiary, fontSize: 12),
                  ),
                  if (draft.author != null && draft.author!.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Icon(Icons.person, size: 12, color: AppTheme.textTertiary),
                    const SizedBox(width: 4),
                    Text(
                      draft.author!,
                      style: const TextStyle(color: AppTheme.textTertiary, fontSize: 12),
                    ),
                  ],
                  const Spacer(),
                  // Actions
                  _IconButton(
                    icon: Icons.edit_outlined,
                    tooltip: 'Edit',
                    onTap: onEdit,
                  ),
                  _IconButton(
                    icon: Icons.send_outlined,
                    tooltip: 'Publish',
                    onTap: onPublish,
                  ),
                  _IconButton(
                    icon: Icons.delete_outline,
                    tooltip: 'Delete',
                    color: AppTheme.error,
                    onTap: onDelete,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

class _PublishedCard extends StatelessWidget {
  final WeChatArticle article;

  const _PublishedCard({required this.article});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppTheme.surface,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppTheme.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    article.title.isEmpty ? 'Untitled' : article.title,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'PUBLISHED',
                    style: TextStyle(
                      color: AppTheme.success,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _StatChip(
                  icon: Icons.remove_red_eye_outlined,
                  value: article.readCount,
                  label: 'reads',
                ),
                const SizedBox(width: 16),
                _StatChip(
                  icon: Icons.favorite_outline,
                  value: article.likeCount,
                  label: 'likes',
                ),
                const Spacer(),
                Text(
                  _formatDate(article.publishTime),
                  style: const TextStyle(color: AppTheme.textTertiary, fontSize: 12),
                ),
              ],
            ),
            if (article.url != null) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: () {
                  // Open URL
                },
                child: Text(
                  article.url!,
                  style: const TextStyle(
                    color: AppTheme.accent,
                    fontSize: 12,
                    decoration: TextDecoration.underline,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final int value;
  final String label;

  const _StatChip({required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppTheme.textSecondary),
        const SizedBox(width: 4),
        Text(
          '$value',
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 2),
        Text(
          label,
          style: const TextStyle(color: AppTheme.textTertiary, fontSize: 12),
        ),
      ],
    );
  }
}

class _IconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color? color;
  final VoidCallback? onTap;

  const _IconButton({
    required this.icon,
    required this.tooltip,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Tooltip(
          message: tooltip,
          child: Icon(icon, size: 18, color: color ?? AppTheme.textSecondary),
        ),
      ),
    );
  }
}
