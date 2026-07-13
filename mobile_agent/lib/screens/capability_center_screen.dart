import 'dart:async';

import 'package:flutter/material.dart';

import '../services/capability_surface_service.dart';
import '../services/cli_hub_catalog_service.dart';
import '../services/linux_sandbox_provider.dart';
import '../services/mobilecode_build_profile.dart';
import '../themes/app_theme.dart';
import 'extension_center_screen.dart';
import 'linux_sandbox_screen.dart';
import 'settings_screen.dart';
import 'subscription_usage_hub_screen.dart';

class CapabilityCenterScreen extends StatefulWidget {
  const CapabilityCenterScreen({
    super.key,
    this.capabilityService = const CapabilitySurfaceService(),
    this.catalogService = const CliHubCatalogService(),
    LinuxSandboxRuntimeProvider? linuxSandboxProvider,
    this.includePreviewCliCatalog =
        MobileCodeBuildProfile.includePreviewCliCatalog,
  }) : linuxSandboxProvider = linuxSandboxProvider;

  final CapabilitySurfaceService capabilityService;
  final CliHubCatalogService catalogService;
  final LinuxSandboxRuntimeProvider? linuxSandboxProvider;
  final bool includePreviewCliCatalog;

  @override
  State<CapabilityCenterScreen> createState() => _CapabilityCenterScreenState();
}

class _CapabilityCenterScreenState extends State<CapabilityCenterScreen> {
  late Future<CliHubCatalog> _catalogFuture;
  late final LinuxSandboxRuntimeProvider _linuxSandboxProvider;
  bool _alpineInstalled = MobileCodeBuildProfile.bundledAlpineRuntime;

  @override
  void initState() {
    super.initState();
    _linuxSandboxProvider =
        widget.linuxSandboxProvider ?? LinuxSandboxRuntimeProvider();
    _catalogFuture = widget.catalogService.loadBundledCatalog().then(
          (catalog) => widget.catalogService.catalogForBuildProfile(
            catalog,
            includePreviewAndPlanned: widget.includePreviewCliCatalog,
          ),
        );
    unawaited(_refreshLinuxSandboxState());
  }

  Future<void> _refreshLinuxSandboxState() async {
    try {
      await _linuxSandboxProvider.initialize();
    } catch (_) {
      // Keep the optimistic build-profile default; the full CLI Hub can show
      // detailed recovery for native status errors.
    }
    if (!mounted) return;
    setState(() {
      _alpineInstalled = _linuxSandboxProvider.state.installed;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: AppTheme.auroraBackground,
        appBar: AppBar(
          title: const Text('能力中心'),
          backgroundColor: AppTheme.auroraBackground,
          foregroundColor: AppTheme.auroraText,
          elevation: 0,
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: '运行环境'),
              Tab(text: '扩展中心'),
              Tab(text: '账号订阅'),
              Tab(text: '安全权限'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _CapabilityList(
              headline: '默认本地运行链路',
              caption:
                  'Native Helper 优先；Alpine 提供内置 CLI runtime；Termux 只作为 fallback。',
              trailingAction: FilledButton.icon(
                onPressed: () => _push(LinuxSandboxScreen()),
                icon: const Icon(Icons.terminal_outlined),
                label: const Text('Sandbox 管理'),
              ),
              cards: [
                for (final item in widget.capabilityService
                    .runtimeSurfaces(alpineInstalled: _alpineInstalled))
                  _CapabilityCard(
                    item: item,
                  ),
              ],
            ),
            FutureBuilder<CliHubCatalog>(
              future: _catalogFuture,
              builder: (context, snapshot) {
                final catalog = snapshot.data;
                final entries = catalog?.entries ?? const <CliHubEntry>[];
                final supported = entries
                    .where((entry) =>
                        entry.supportLevel == CliHubSupportLevel.supported)
                    .length;
                final preview = entries
                    .where((entry) =>
                        entry.supportLevel == CliHubSupportLevel.preview)
                    .length;
                final planned = entries
                    .where((entry) =>
                        entry.supportLevel == CliHubSupportLevel.planned)
                    .length;
                return _CapabilityList(
                  headline: '扩展中心 / CLI Hub',
                  caption: catalog == null
                      ? '正在读取 catalog...'
                      : '${entries.length} 个 CLI · 扩展中心负责安装、检测、登录状态和 typed task。',
                  trailingAction: FilledButton.icon(
                    onPressed: () => _push(
                      ExtensionCenterScreen(
                        includePreviewCliCatalog:
                            widget.includePreviewCliCatalog,
                      ),
                    ),
                    icon: const Icon(Icons.extension_outlined),
                    label: const Text('打开 CLI Hub'),
                  ),
                  cards: [
                    if (snapshot.hasError)
                      _StatusMessage(
                        icon: Icons.error_outline,
                        color: AppTheme.error,
                        text: snapshot.error.toString(),
                      ),
                    if (catalog != null)
                      _ExtensionHubSummaryCard(
                        total: entries.length,
                        supported: supported,
                        preview: preview,
                        planned: planned,
                        policy: MobileCodeBuildProfile.cliCatalogPolicy,
                      ),
                  ],
                );
              },
            ),
            _CapabilityList(
              headline: '账号与订阅',
              caption:
                  'ProviderLogin -> CredentialVault -> ModelRouter -> ProviderAdapter。',
              trailingAction: FilledButton.icon(
                onPressed: () => _push(SubscriptionUsageHubScreen()),
                icon: const Icon(Icons.account_circle_outlined),
                label: const Text('打开 Usage Hub'),
              ),
              cards: [
                for (final item
                    in widget.capabilityService.integrationSurfaces())
                  _CapabilityCard(
                    item: item,
                  ),
              ],
            ),
            _CapabilityList(
              headline: '权限与安全',
              caption: '授权、凭据和 evidence redaction 独立于 Runtime 和 CLI。',
              trailingAction: FilledButton.icon(
                onPressed: () => _push(
                  const SettingsScreen(
                    initialSection: SettingsInitialSection.harnessPermission,
                  ),
                ),
                icon: const Icon(Icons.health_and_safety_outlined),
                label: const Text('权限设置'),
              ),
              cards: const [
                _SecurityCard(
                  icon: Icons.accessibility_new_outlined,
                  title: '无障碍服务',
                  subtitle: 'PhoneUseAccessibilityService 状态检测和系统设置跳转。',
                  state: CapabilityState.needsSetup,
                ),
                _SecurityCard(
                  icon: Icons.battery_saver_outlined,
                  title: '后台运行权限',
                  subtitle: '应用详情、电池优化和后台保活说明。',
                  state: CapabilityState.needsSetup,
                ),
                _SecurityCard(
                  icon: Icons.lock_outline,
                  title: 'Credential Vault',
                  subtitle:
                      '账号 token/cookie 不进入 Runtime、SharedPreferences、日志或截图。',
                  state: CapabilityState.available,
                ),
                _SecurityCard(
                  icon: Icons.fact_check_outlined,
                  title: 'Evidence / logs redaction',
                  subtitle: '长任务和 CLI 输出必须过滤 token、cookie、.env 和本地私密路径。',
                  state: CapabilityState.available,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _push(Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }
}

class _CapabilityList extends StatelessWidget {
  const _CapabilityList({
    required this.headline,
    required this.caption,
    required this.cards,
    this.trailingAction,
  });

  final String headline;
  final String caption;
  final List<Widget> cards;
  final Widget? trailingAction;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      style: AppTheme.zhTitleLarge.copyWith(
                        color: AppTheme.auroraText,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      caption,
                      style: AppTheme.zhBody.copyWith(
                        color: AppTheme.auroraTextMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailingAction != null) ...[
                const SizedBox(width: 12),
                trailingAction!,
              ],
            ],
          ),
          const SizedBox(height: 16),
          for (final card in cards) ...[
            card,
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _CapabilityCard extends StatelessWidget {
  const _CapabilityCard({
    required this.item,
  });

  final CapabilitySurfaceDescriptor item;

  @override
  Widget build(BuildContext context) {
    final color = _stateColor(item.state);
    return Material(
      color: AppTheme.auroraSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppTheme.auroraBorder),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(_iconForType(item.type), color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: AppTheme.zhTitleMedium.copyWith(
                            color: AppTheme.auroraText,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.subtitle,
                          style: AppTheme.zhBody.copyWith(
                            color: AppTheme.auroraTextMuted,
                            fontSize: 12,
                            height: 1.32,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Pill(label: item.state.name, color: color),
                  _Pill(label: 'risk:${item.riskLevel.name}'),
                  _Pill(label: 'credential:${item.credentialPolicy.name}'),
                  if (item.installProfile != null)
                    _Pill(label: 'profile:${item.installProfile}'),
                  if (item.probeTaskKind != null)
                    _Pill(label: 'probe:${item.probeTaskKind}'),
                  if (item.boundary.safe) const _Pill(label: 'safe bridge'),
                ],
              ),
              if (item.readOnlyTaskKinds.isNotEmpty ||
                  item.mutationTaskKinds.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  _taskSummary(item),
                  style: const TextStyle(
                    color: AppTheme.auroraTextFaint,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SecurityCard extends StatelessWidget {
  const _SecurityCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.state,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final CapabilityState state;

  @override
  Widget build(BuildContext context) {
    final color = _stateColor(state);
    return Material(
      color: AppTheme.auroraSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppTheme.auroraBorder),
      ),
      child: ListTile(
        minVerticalPadding: 12,
        leading: Icon(icon, color: color),
        title: Text(
          title,
          style: AppTheme.zhTitleMedium.copyWith(
            color: AppTheme.auroraText,
            fontSize: 16,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: AppTheme.zhBody.copyWith(
            color: AppTheme.auroraTextMuted,
            fontSize: 12,
          ),
        ),
        trailing: _Pill(label: state.name, color: color),
      ),
    );
  }
}

class _ExtensionHubSummaryCard extends StatelessWidget {
  const _ExtensionHubSummaryCard({
    required this.total,
    required this.supported,
    required this.preview,
    required this.planned,
    required this.policy,
  });

  final int total;
  final int supported;
  final int preview;
  final int planned;
  final String policy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.auroraSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppTheme.auroraBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppTheme.auroraCyan.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.extension_outlined,
                    color: AppTheme.auroraCyan,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CLI Hub 摘要',
                        style: AppTheme.zhTitleMedium.copyWith(
                          color: AppTheme.auroraText,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '完整安装、检测和账号状态统一在扩展中心管理。',
                        style: AppTheme.zhBody.copyWith(
                          color: AppTheme.auroraTextMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Pill(label: '$total total', color: AppTheme.auroraCyan),
                _Pill(label: '$supported supported'),
                _Pill(label: '$preview preview'),
                _Pill(label: '$planned planned'),
                const _Pill(label: 'CLI 按需安装'),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              policy,
              style: AppTheme.zhBody.copyWith(
                color: AppTheme.auroraTextMuted,
                fontSize: 12,
                height: 1.32,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.auroraSurface,
        borderRadius: BorderRadius.circular(8),
        border: const Border.fromBorderSide(
          BorderSide(color: AppTheme.auroraBorder),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    this.color = AppTheme.auroraTextFaint,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontFamily: AppTheme.fontBody,
          fontFamilyFallback: AppTheme.fontFallback,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

Color _stateColor(CapabilityState state) {
  return switch (state) {
    CapabilityState.installed => AppTheme.auroraCyan,
    CapabilityState.available => AppTheme.success,
    CapabilityState.authenticated => AppTheme.auroraBlue,
    CapabilityState.needsSetup => AppTheme.warning,
    CapabilityState.blocked => AppTheme.error,
    CapabilityState.error => AppTheme.error,
  };
}

IconData _iconForType(CapabilitySurfaceType type) {
  return switch (type) {
    CapabilitySurfaceType.runtimeProvider => Icons.memory_outlined,
    CapabilitySurfaceType.integrationProvider => Icons.account_tree_outlined,
    CapabilitySurfaceType.cliExtensionProvider => Icons.terminal_outlined,
  };
}

String _taskSummary(CapabilitySurfaceDescriptor item) {
  final readOnly = item.readOnlyTaskKinds.isEmpty
      ? 'read-only:none'
      : 'read-only:${item.readOnlyTaskKinds.join(', ')}';
  final mutation = item.mutationTaskKinds.isEmpty
      ? 'mutation:none'
      : 'mutation:${item.mutationTaskKinds.join(', ')}';
  return '$readOnly\n$mutation';
}
