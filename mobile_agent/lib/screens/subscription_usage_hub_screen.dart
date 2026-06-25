import 'dart:async';

import 'package:flutter/material.dart';

import '../services/github_deep_service.dart';
import '../services/subscription_usage_service.dart';
import 'github_screen.dart';

const _hubBg = Color(0xFFF8F7F3);
const _hubText = Color(0xFF151515);
const _hubMuted = Color(0xFF6D6D6A);
const _hubLine = Color(0xFFD8D5CC);
const _hubPanel = Color(0xFFFFFFFF);
const _hubTrack = Color(0xFFEAE8E0);
const _hubLilac = Color(0xFFEDE7FF);

class SubscriptionUsageHubScreen extends StatefulWidget {
  SubscriptionUsageHubScreen({
    super.key,
    SubscriptionUsageService? service,
  }) : service = service ?? SubscriptionUsageService.instance;

  final SubscriptionUsageService service;

  @override
  State<SubscriptionUsageHubScreen> createState() =>
      _SubscriptionUsageHubScreenState();
}

class _SubscriptionUsageHubScreenState
    extends State<SubscriptionUsageHubScreen> {
  late SubscriptionProviderState _selected;
  late final GitHubDeepService _github;
  bool _officialLoginBusy = false;

  @override
  void initState() {
    super.initState();
    _github = GitHubDeepService();
    widget.service.addListener(_handleServiceChanged);
    _selected = widget.service.states.first;
    unawaited(_initializeLinkedAccounts());
  }

  @override
  void dispose() {
    widget.service.removeListener(_handleServiceChanged);
    super.dispose();
  }

  void _handleServiceChanged() {
    if (!mounted) return;
    setState(() {
      _selected = widget.service.states.firstWhere(
        (state) => state.provider.id == _selected.provider.id,
        orElse: () => widget.service.states.first,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final states = widget.service.states;
    return Scaffold(
      backgroundColor: _hubBg,
      appBar: AppBar(
        backgroundColor: _hubBg,
        foregroundColor: _hubText,
        elevation: 0,
        title: const Text('Usage Hub'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: () => unawaited(
                widget.service.refreshMockUsage(_selected.provider.id)),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Text(
            _selected.provider.name,
            style: const TextStyle(
              color: _hubText,
              fontSize: 34,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _subtitleFor(_selected),
            style:
                const TextStyle(color: _hubMuted, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 14),
          _ProviderTabs(
            states: states,
            selectedId: _selected.provider.id,
            onSelected: (state) => setState(() => _selected = state),
          ),
          const SizedBox(height: 14),
          for (final quota in _selected.quotas) ...[
            _QuotaCard(
              quota: quota,
              color: Color(_selected.provider.colorValue),
            ),
            const SizedBox(height: 12),
          ],
          _LoginPanel(
            state: _selected,
            busy: _officialLoginBusy,
            onOfficialLogin: () => unawaited(_handleOfficialLogin(_selected)),
            onManualCredential: () =>
                unawaited(_showManualCredentialSheet(_selected)),
            onLogout: _selected.connected
                ? () => unawaited(widget.service.logout(_selected.provider.id))
                : null,
          ),
          const SizedBox(height: 12),
          _PrivacyPanel(snapshot: widget.service.redactedSnapshot()),
        ],
      ),
    );
  }

  String _subtitleFor(SubscriptionProviderState state) {
    if (state.connected) {
      return 'Last updated: ${_formatRelative(state.account?.lastLoginAt)} · mock usage, real credential hidden';
    }
    if (state.account?.failureKind != null) {
      return 'Login recovery: ${state.account!.recoveryHint ?? state.provider.recoveryHint}';
    }
    return '未登录 · 先使用本地 mock quota 预览订阅账户结构';
  }

  Future<void> _initializeLinkedAccounts() async {
    await _github.initialize();
    await _syncGitHubAccount(notifyWhenMissing: false);
  }

  Future<void> _handleOfficialLogin(SubscriptionProviderState state) async {
    if (_officialLoginBusy) return;
    if (state.provider.kind != SubscriptionProviderKind.copilotGithub) {
      await widget.service.planOfficialLogin(state.provider.id);
      return;
    }

    setState(() => _officialLoginBusy = true);
    try {
      await _github.initialize();
      if (!_github.isAuthenticated && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const GitHubScreen()),
        );
        await _github.initialize();
      }
      final synced = await _syncGitHubAccount(notifyWhenMissing: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(synced
              ? 'GitHub account linked from existing secure session'
              : 'No GitHub session found. Complete GitHub login first.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _officialLoginBusy = false);
    }
  }

  Future<bool> _syncGitHubAccount({required bool notifyWhenMissing}) async {
    final username = _github.currentUser;
    if (username == null || username.isEmpty) {
      if (notifyWhenMissing) {
        await widget.service.planOfficialLogin('copilotGithub');
      }
      return false;
    }

    await widget.service.connectExistingProviderAccount(
      providerId: 'copilotGithub',
      displayName: '@$username',
      loginMethod: ProviderLoginMethod.githubOAuth,
      authenticatedAt: _github.authenticatedAtFor(username),
      credentialLocation: 'github_deep_service_secure_storage',
    );
    return true;
  }

  Future<void> _showManualCredentialSheet(
      SubscriptionProviderState state) async {
    final accountController =
        TextEditingController(text: state.provider.accountLabel);
    final credentialController = TextEditingController();
    final result = await showModalBottomSheet<_ManualCredentialResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _hubPanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              18,
              18,
              18 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Manual credential',
                  style: TextStyle(
                    color: _hubText,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '凭据只写入 secure storage。GitHub token 会先验证 /user；不会写入 SharedPreferences、日志、roadmp、截图或 evidence 原文。',
                  style:
                      TextStyle(color: _hubMuted, fontSize: 12, height: 1.35),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: accountController,
                  decoration: const InputDecoration(labelText: 'Account label'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: credentialController,
                  obscureText: true,
                  decoration:
                      const InputDecoration(labelText: 'API key or token'),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(
                          context,
                          _ManualCredentialResult(
                            accountLabel: accountController.text,
                            credential: credentialController.text,
                          ),
                        ),
                        child: const Text('保存'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    accountController.dispose();
    credentialController.dispose();
    if (result == null) return;
    try {
      await widget.service.connectManualCredential(
        providerId: state.provider.id,
        accountLabel: result.accountLabel,
        credential: result.credential,
        method: _manualCredentialMethod(state.provider),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Credential saved to secure storage')),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Credential not saved: $error')),
      );
    }
  }
}

class _ProviderTabs extends StatelessWidget {
  const _ProviderTabs({
    required this.states,
    required this.selectedId,
    required this.onSelected,
  });

  final List<SubscriptionProviderState> states;
  final String selectedId;
  final ValueChanged<SubscriptionProviderState> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 78,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final state = states[index];
          final selected = state.provider.id == selectedId;
          return InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => onSelected(state),
            child: Container(
              width: 134,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: selected ? _hubLilac : _hubPanel,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected ? Color(state.provider.colorValue) : _hubLine,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    state.connected
                        ? Icons.verified_user_outlined
                        : Icons.login_outlined,
                    color: Color(state.provider.colorValue),
                    size: 18,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    state.provider.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _hubText,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemCount: states.length,
      ),
    );
  }
}

class _QuotaCard extends StatelessWidget {
  const _QuotaCard({required this.quota, required this.color});

  final UsageQuota quota;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _hubPanel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _hubLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  quota.title,
                  style: const TextStyle(
                    color: _hubText,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _StateChip(quota: quota),
            ],
          ),
          const SizedBox(height: 12),
          _ProgressBar(
              value: quota.usagePercent,
              secondaryValue: quota.timePercent,
              color: color),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: Text(
                      '流量消耗: ${(quota.usagePercent * 100).toStringAsFixed(0)}%')),
              Text('时间: ${(quota.timePercent * 100).toStringAsFixed(0)}%'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            quota.errorMessage ?? '${_formatReset(quota.resetAt)} 重置',
            style: const TextStyle(color: _hubMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.value,
    required this.secondaryValue,
    required this.color,
  });

  final double value;
  final double secondaryValue;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: 16,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: _hubTrack),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: secondaryValue.clamp(0, 1),
              child: ColoredBox(color: color.withOpacity(0.24)),
            ),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value.clamp(0, 1),
              child: ColoredBox(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.quota});

  final UsageQuota quota;

  @override
  Widget build(BuildContext context) {
    final label = switch (quota.refreshState) {
      SubscriptionRefreshState.refreshing => '刷新中',
      SubscriptionRefreshState.success => quota.mock ? 'Mock' : '真实',
      SubscriptionRefreshState.error => '错误',
      SubscriptionRefreshState.idle => '预览',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _hubLilac,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12, color: _hubText)),
    );
  }
}

class _LoginPanel extends StatelessWidget {
  const _LoginPanel({
    required this.state,
    required this.busy,
    required this.onOfficialLogin,
    required this.onManualCredential,
    required this.onLogout,
  });

  final SubscriptionProviderState state;
  final bool busy;
  final VoidCallback onOfficialLogin;
  final VoidCallback onManualCredential;
  final VoidCallback? onLogout;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _hubPanel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _hubLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            state.connected
                ? 'Connected: ${state.account!.displayName}'
                : 'Login method',
            style: const TextStyle(
              color: _hubText,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            state.provider.recoveryHint,
            style:
                const TextStyle(color: _hubMuted, fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: busy ? null : onOfficialLogin,
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.open_in_browser_outlined),
            label: Text(busy
                ? '连接中...'
                : '使用 ${_primaryMethodLabel(state.provider)} 登录'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(state.provider.colorValue),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onManualCredential,
            icon: const Icon(Icons.key_outlined),
            label: const Text('手动添加 API key / token'),
          ),
          if (onLogout != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onLogout,
              icon: const Icon(Icons.logout_outlined),
              label: const Text('清除本地凭据'),
            ),
          ],
        ],
      ),
    );
  }
}

class _PrivacyPanel extends StatelessWidget {
  const _PrivacyPanel({required this.snapshot});

  final Map<String, Object?> snapshot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _hubPanel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _hubLine),
      ),
      child: const Text(
        'Privacy: credentials are redacted from UI state and are only written through secure storage. AIUsage is used as information architecture reference only.',
        style: TextStyle(color: _hubMuted, fontSize: 12, height: 1.35),
      ),
    );
  }
}

class _ManualCredentialResult {
  const _ManualCredentialResult({
    required this.accountLabel,
    required this.credential,
  });

  final String accountLabel;
  final String credential;
}

ProviderLoginMethod _manualCredentialMethod(SubscriptionProvider provider) {
  if (provider.loginMethods.contains(ProviderLoginMethod.manualAccessToken)) {
    return ProviderLoginMethod.manualAccessToken;
  }
  return ProviderLoginMethod.manualApiKey;
}

String _primaryMethodLabel(SubscriptionProvider provider) {
  final method = provider.loginMethods.first;
  return switch (method) {
    ProviderLoginMethod.githubOAuth => 'GitHub',
    ProviderLoginMethod.googleAccount => 'Google',
    ProviderLoginMethod.officialBrowser =>
      provider.name.split('/').first.trim(),
    ProviderLoginMethod.manualApiKey => 'API key',
    ProviderLoginMethod.manualAccessToken => 'token',
  };
}

String _formatRelative(DateTime? value) {
  if (value == null) return 'never';
  final diff = DateTime.now().difference(value);
  if (diff.inMinutes < 1) return 'less than a minute ago';
  if (diff.inHours < 1) return '${diff.inMinutes} minutes ago';
  return '${diff.inHours} hours ago';
}

String _formatReset(DateTime value) {
  final now = DateTime.now();
  final diff = value.difference(now);
  if (diff.inMinutes < 60) return '${diff.inMinutes.clamp(0, 59)} 分钟后';
  if (diff.inHours < 24)
    return '${diff.inHours} 小时 ${diff.inMinutes.remainder(60)} 分钟后';
  return '${value.month}月${value.day}日';
}
