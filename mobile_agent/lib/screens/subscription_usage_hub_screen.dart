import 'dart:async';

import 'package:flutter/material.dart';

import '../services/cli_hub_runtime_events.dart';
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
const _hubSoftGreen = Color(0xFFE8F3EE);
const _hubSoftBlue = Color(0xFFE8F0FB);

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
  StreamSubscription<CliHubRuntimeEvent>? _cliHubEvents;
  bool _officialLoginBusy = false;

  @override
  void initState() {
    super.initState();
    _github = GitHubDeepService();
    widget.service.addListener(_handleServiceChanged);
    _selected = widget.service.states.first;
    _cliHubEvents = CliHubRuntimeEvents.stream.listen(_handleCliHubEvent);
    unawaited(_initializeLinkedAccounts());
  }

  @override
  void dispose() {
    unawaited(_cliHubEvents?.cancel());
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

  void _handleCliHubEvent(CliHubRuntimeEvent event) {
    if (!event.success || !event.changesInstallOrAuthState) return;
    final providerId = switch (event.cliId) {
      'github-cli' => 'copilotGithub',
      'google-workspace-cli' => 'antigravityGoogle',
      _ => null,
    };
    if (providerId == null) return;
    unawaited(widget.service.refreshMockUsage(providerId));
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
          _UsageHero(
            state: _selected,
            onRefresh: () => unawaited(
              widget.service.refreshMockUsage(_selected.provider.id),
            ),
          ),
          const SizedBox(height: 14),
          _ProviderDock(
            states: states,
            selectedId: _selected.provider.id,
            onSelected: (state) => setState(() => _selected = state),
          ),
          const SizedBox(height: 18),
          _SectionLabel(
            title: 'Quota',
            value: _selected.connected ? '真实账户' : '本地预览',
          ),
          const SizedBox(height: 10),
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

class _UsageHero extends StatelessWidget {
  const _UsageHero({
    required this.state,
    required this.onRefresh,
  });

  final SubscriptionProviderState state;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final accent = Color(state.provider.colorValue);
    final connected = state.connected;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 14, 16),
      decoration: BoxDecoration(
        color: _hubPanel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _hubLine),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProviderMark(provider: state.provider, selected: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.provider.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _hubText,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        height: 0.98,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      connected
                          ? 'Last updated: ${_formatRelative(state.account?.lastLoginAt)}'
                          : 'Last updated: local preview',
                      style: const TextStyle(
                        color: _hubMuted,
                        fontSize: 13,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '刷新',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: connected ? _hubSoftGreen : _hubSoftBlue,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: accent.withValues(alpha: 0.22)),
            ),
            child: Row(
              children: [
                Icon(
                  connected
                      ? Icons.verified_user_outlined
                      : Icons.visibility_outlined,
                  color: accent,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '会话状态',
                        style: TextStyle(
                          color: _hubText,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        connected
                            ? '${state.account!.displayName} · credential redacted'
                            : '未登录 · 使用 mock quota 预览订阅账户结构',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _hubMuted,
                          fontSize: 12,
                          height: 1.28,
                        ),
                      ),
                    ],
                  ),
                ),
                _ConnectionPill(connected: connected, hasError: state.hasError),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: _hubText,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: _hubMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ProviderDock extends StatelessWidget {
  const _ProviderDock({
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
      height: 124,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final state = states[index];
          final selected = state.provider.id == selectedId;
          return InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => onSelected(state),
            child: Container(
              width: 132,
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 9),
              decoration: BoxDecoration(
                color: selected ? _hubText : _hubPanel,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected ? _hubText : _hubLine,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ProviderMark(
                    provider: state.provider,
                    selected: selected,
                    connected: state.connected,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    state.provider.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Colors.white : _hubText,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    state.connected ? '已登录' : '预览',
                    style: TextStyle(
                      color: selected ? Colors.white70 : _hubMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
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

class _ProviderMark extends StatelessWidget {
  const _ProviderMark({
    required this.provider,
    required this.selected,
    this.connected = false,
  });

  final SubscriptionProvider provider;
  final bool selected;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final accent = Color(provider.colorValue);
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: selected
            ? Colors.white.withValues(alpha: 0.16)
            : accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            _providerIcon(provider.kind),
            color: selected ? Colors.white : accent,
            size: 24,
          ),
          if (connected)
            Positioned(
              right: 5,
              bottom: 5,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: selected ? Colors.white : const Color(0xFF1B9E5A),
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ConnectionPill extends StatelessWidget {
  const _ConnectionPill({required this.connected, required this.hasError});

  final bool connected;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final label = hasError ? '错误' : (connected ? '已登录' : '预览');
    final color = hasError
        ? const Color(0xFFB3261E)
        : (connected ? const Color(0xFF1B9E5A) : const Color(0xFF2F7DE1));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
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
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
      decoration: BoxDecoration(
        color: _hubPanel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _hubLine),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
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
                child: _QuotaMetric(
                  label: '流量消耗',
                  value: '${(quota.usagePercent * 100).toStringAsFixed(0)}%',
                ),
              ),
              _QuotaMetric(
                label: '时间',
                value: '${(quota.timePercent * 100).toStringAsFixed(0)}%',
                alignEnd: true,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                quota.errorMessage == null
                    ? Icons.schedule_outlined
                    : Icons.error_outline,
                color: quota.errorMessage == null
                    ? _hubMuted
                    : const Color(0xFFB3261E),
                size: 16,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  quota.errorMessage ?? '${_formatReset(quota.resetAt)} 重置',
                  style: TextStyle(
                    color: quota.errorMessage == null
                        ? _hubMuted
                        : const Color(0xFFB3261E),
                    fontSize: 13,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuotaMetric extends StatelessWidget {
  const _QuotaMetric({
    required this.label,
    required this.value,
    this.alignEnd = false,
  });

  final String label;
  final String value;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _hubMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: _hubText,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
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
              child: ColoredBox(color: color.withValues(alpha: 0.24)),
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
    final accent = Color(state.provider.colorValue);
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
          Row(
            children: [
              Expanded(
                child: Text(
                  state.connected
                      ? 'Connected: ${state.account!.displayName}'
                      : 'Login method',
                  style: const TextStyle(
                    color: _hubText,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _LoginMethodChip(method: state.provider.loginMethods.first),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            state.provider.recoveryHint,
            style:
                const TextStyle(color: _hubMuted, fontSize: 12, height: 1.35),
          ),
          if (state.account?.failureKind ==
              'official_flow_not_connected_locally') ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4E5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFFD8A8)),
              ),
              child: const Text(
                '官方登录入口已规划，当前先保留 mock quota 预览；接入 provider 官方能力后再刷新真实额度。',
                style: TextStyle(
                  color: Color(0xFF8A4B00),
                  fontSize: 12,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            height: 58,
            child: ElevatedButton.icon(
              onPressed: busy ? null : onOfficialLogin,
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.open_in_browser_outlined),
              label: Text(
                busy
                    ? '连接中...'
                    : '使用 ${_primaryMethodLabel(state.provider)} 登录',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                textStyle: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onManualCredential,
            icon: const Icon(Icons.key_outlined),
            label: const Text('手动添加 API key / token'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _hubText,
              side: const BorderSide(color: _hubLine),
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(99),
              ),
            ),
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

class _LoginMethodChip extends StatelessWidget {
  const _LoginMethodChip({required this.method});

  final ProviderLoginMethod method;

  @override
  Widget build(BuildContext context) {
    final label = switch (method) {
      ProviderLoginMethod.officialBrowser => '官方浏览器',
      ProviderLoginMethod.githubOAuth => 'GitHub OAuth',
      ProviderLoginMethod.googleAccount => 'Google 账号',
      ProviderLoginMethod.manualApiKey => 'API key',
      ProviderLoginMethod.manualAccessToken => 'Token',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _hubLilac,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: _hubText,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.lock_outline, color: _hubText, size: 18),
              SizedBox(width: 8),
              Text(
                'Privacy boundary',
                style: TextStyle(
                  color: _hubText,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Credentials are redacted from UI state and are only written through secure storage. AIUsage is used as information architecture reference only.',
            style: TextStyle(color: _hubMuted, fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              _BoundaryChip(label: 'no cookie scraping'),
              _BoundaryChip(label: 'no raw screenshots'),
              _BoundaryChip(label: 'no roadmp secrets'),
            ],
          ),
        ],
      ),
    );
  }
}

class _BoundaryChip extends StatelessWidget {
  const _BoundaryChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: _hubSoftGreen,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: _hubText,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
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

IconData _providerIcon(SubscriptionProviderKind kind) {
  return switch (kind) {
    SubscriptionProviderKind.claude => Icons.auto_awesome,
    SubscriptionProviderKind.copilotGithub => Icons.hub_outlined,
    SubscriptionProviderKind.antigravityGoogle => Icons.travel_explore,
    SubscriptionProviderKind.codexChatGpt => Icons.bubble_chart_outlined,
  };
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
