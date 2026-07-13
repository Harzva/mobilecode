import 'package:flutter/material.dart';

import '../services/linux_sandbox_provider.dart';
import '../themes/app_theme.dart';
import '../widgets/glass_card_widget.dart';
import '../widgets/linux_sandbox_task_card.dart';

class LinuxSandboxScreen extends StatefulWidget {
  LinuxSandboxScreen({
    super.key,
    LinuxSandboxRuntimeProvider? provider,
  }) : provider = provider ?? LinuxSandboxRuntimeProvider();

  final LinuxSandboxRuntimeProvider provider;

  @override
  State<LinuxSandboxScreen> createState() => _LinuxSandboxScreenState();
}

class _LinuxSandboxScreenState extends State<LinuxSandboxScreen> {
  bool _busy = false;
  Map<String, dynamic>? _lastTaskResult;

  LinuxSandboxRuntimeProvider get provider => widget.provider;

  @override
  Widget build(BuildContext context) {
    final state = provider.state;
    final manifest = state.manifest;
    return Scaffold(
      backgroundColor: AppTheme.deepSpace,
      appBar: AppBar(
        title: const Text('Linux Sandbox'),
        backgroundColor: AppTheme.deepSpace,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _HeroPanel(
            installed: state.installed,
            status: state.status,
            progress: state.progress,
            arch: manifest.arch,
            version: manifest.version,
            busy: _busy,
            onInstall: _installRootfs,
            onReset: _deleteRootfs,
          ),
          const SizedBox(height: 14),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(label: 'Package Profiles'),
              _Pill(label: 'Base'),
              _Pill(label: 'Dev Basic'),
              _Pill(label: 'Python Pack'),
              _Pill(label: 'Node Pack'),
            ],
          ),
          const SizedBox(height: 14),
          GlassCardWidget(
            borderRadius: 12,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionTitle(
                    icon: Icons.verified_outlined,
                    title: 'Rootfs Manifest',
                    subtitle:
                        'Alpine Linux rootfs · 下载、校验和解包都限制在 app-owned storage',
                  ),
                  const SizedBox(height: 10),
                  const _Pill(label: 'Alpine Linux rootfs'),
                  const SizedBox(height: 16),
                  _InfoRow(label: '版本', value: manifest.version),
                  _InfoRow(label: '架构', value: manifest.arch),
                  _InfoRow(
                    label: '大小',
                    value:
                        '${(manifest.compressedSizeBytes / 1024 / 1024).toStringAsFixed(1)} MB',
                  ),
                  _InfoRow(label: '来源', value: manifest.source),
                  _InfoRow(
                    label: 'SHA-256',
                    value: '${manifest.sha256.substring(0, 12)}...'
                        '${manifest.sha256.substring(manifest.sha256.length - 8)}',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Agent 只看到 typed tasks；raw shell 默认关闭。包源、checksum 和安装结果都会写入 evidence。',
                    style: TextStyle(color: AppTheme.textTertiary),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        key: const ValueKey('linuxSandbox.installRootfs'),
                        onPressed: _busy ? null : _installRootfs,
                        icon: Icon(state.installed
                            ? Icons.refresh
                            : Icons.download_outlined),
                        label: Text(
                            state.status == LinuxSandboxInstallStatus.failed
                                ? '重试'
                                : state.installed
                                    ? '重新校验'
                                    : '下载 rootfs'),
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey('linuxSandbox.cancelRootfs'),
                        onPressed: _busy ? provider.cancelRootfsInstall : null,
                        icon: const Icon(Icons.cancel_outlined),
                        label: const Text('取消'),
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey('linuxSandbox.deleteRootfs'),
                        onPressed: _busy ? null : _deleteRootfs,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('删除/重置'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          GlassCardWidget(
            borderRadius: 12,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionTitle(
                    icon: Icons.inventory_2_outlined,
                    title: 'Package Profiles',
                    subtitle: '按需安装开发包，安装后验证实际命令能力',
                  ),
                  const SizedBox(height: 12),
                  ...state.packageProfiles.map(
                    (profile) => _PackageProfileRow(
                      label: profile.label,
                      packages: profile.packages,
                      status: profile.status.name,
                      installed: profile.installed,
                      enabled: !_busy,
                      downloadMb: profile.estimatedDownloadBytes / 1024 / 1024,
                      installedMb:
                          profile.estimatedInstalledBytes / 1024 / 1024,
                      recoveryHint: profile.recoveryHint,
                      onPreview: () => _previewPackageProfile(profile.id),
                      onInstall: () => _confirmInstallPackageProfile(profile),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          LinuxSandboxTaskCard(
            preview: const LinuxSandboxTaskPreview(
              taskKind: 'project_check',
              cwd: '/workspace',
              args: ['--typed', '--no-raw-shell'],
              timeout: Duration(seconds: 30),
              capability: 'rootfsVerified + workspace validation',
              impact: '只读检查项目结构，不安装包，不写入文件',
            ),
            installed: state.installed,
            onInstall: _installRootfs,
            onRun: _runProjectCheck,
          ),
          if (_lastTaskResult != null) ...[
            const SizedBox(height: 16),
            GlassCardWidget(
              borderRadius: 12,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionTitle(
                      icon: Icons.receipt_long_outlined,
                      title: 'Last Task Evidence',
                      subtitle: '只展示摘要，完整输出由 ActionEvidence 记录',
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${_lastTaskResult!['status']} · '
                      'failure=${_lastTaskResult!['failureKind'] ?? 'none'}\n'
                      '${_lastTaskResult!['stderr'] ?? ''}',
                      style: const TextStyle(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          const GlassCardWidget(
            borderRadius: 12,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionTitle(
                    icon: Icons.shield_outlined,
                    title: 'Security gate',
                    subtitle: '内置路径，不依赖 Termux；Agent 默认不能执行任意 shell',
                  ),
                  SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Pill(label: 'app-owned rootfs'),
                      _Pill(label: 'SHA verified'),
                      _Pill(label: 'typed tasks only'),
                      _Pill(label: 'raw shell blocked'),
                      _Pill(label: 'redacted logs'),
                      _Pill(label: 'approval required'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _installRootfs() async {
    setState(() => _busy = true);
    final state = await provider.installRootfs();
    if (!mounted) return;
    setState(() => _busy = false);
    _showSnack(
      state.installed ? 'rootfs 已安装并校验' : state.recoveryHint ?? 'rootfs 安装失败',
    );
  }

  Future<void> _deleteRootfs() async {
    setState(() => _busy = true);
    await provider.deleteRootfs();
    if (!mounted) return;
    setState(() => _busy = false);
    _showSnack('rootfs 已删除，可重新安装');
  }

  Future<void> _runProjectCheck() async {
    final result = await provider.runTypedTask(
      taskKind: 'project_check',
      payload: const {
        'cwd': '/workspace',
        'args': ['--typed', '--no-raw-shell'],
      },
    );
    if (!mounted) return;
    setState(() => _lastTaskResult = result);
  }

  void _previewPackageProfile(String profileId) {
    final evidence = provider.previewPackageProfileInstall(profileId);
    _showSnack(
      '${evidence.metadata['profileName'] ?? profileId}: '
      '${evidence.failureKind ?? 'preview'}',
    );
  }

  Future<void> _confirmInstallPackageProfile(
    LinuxSandboxPackageProfile profile,
  ) async {
    if (!provider.state.installed) {
      _showSnack('请先安装并校验 rootfs，再选择 Package Profile');
      return;
    }
    if (profile.installed) {
      _showSnack('${profile.label} 已安装');
      return;
    }
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('安装 ${profile.label}?'),
        content: Text(
          '将安装：${profile.packages.join(', ')}\n\n'
          '预计下载 ${(profile.estimatedDownloadBytes / 1024 / 1024).toStringAsFixed(1)} MB，'
          '安装后占用 ${(profile.estimatedInstalledBytes / 1024 / 1024).toStringAsFixed(1)} MB。\n\n'
          '安装会通过 Linux Sandbox typed task 执行，并写入 ActionEvidence。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('安装'),
          ),
        ],
      ),
    );
    if (approved != true) return;

    setState(() => _busy = true);
    final result = await provider.runTypedTask(
      taskKind: 'package_install',
      payload: {
        'profileId': profile.id,
        'approved': true,
      },
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _lastTaskResult = result;
    });
    _showSnack(
      result['success'] == true
          ? '${profile.label} 已安装'
          : '${profile.label} 安装失败：${result['failureKind'] ?? 'unknown'}',
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.installed,
    required this.status,
    required this.progress,
    required this.arch,
    required this.version,
    required this.busy,
    required this.onInstall,
    required this.onReset,
  });

  final bool installed;
  final LinuxSandboxInstallStatus status;
  final double progress;
  final String arch;
  final String version;
  final bool busy;
  final VoidCallback onInstall;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final statusLabel = installed ? 'Ready' : status.name;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border.withOpacity(0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: installed
                      ? AppTheme.success.withOpacity(0.16)
                      : AppTheme.cyan.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  installed ? Icons.terminal : Icons.cloud_download_outlined,
                  color: installed ? AppTheme.success : AppTheme.cyan,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Built-in Alpine Runtime',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$version · $arch · $statusLabel',
                      style: const TextStyle(color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      installed ? '已安装并通过校验' : '未安装：需要先下载并校验 rootfs',
                      style: const TextStyle(
                        color: AppTheme.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusDot(ready: installed),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: installed ? 1 : progress.clamp(0, 1),
              backgroundColor: AppTheme.surfaceElevated,
              valueColor: AlwaysStoppedAnimation<Color>(
                installed ? AppTheme.success : AppTheme.cyan,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy ? null : onInstall,
                  icon: Icon(installed ? Icons.verified : Icons.download),
                  label: Text(installed ? 'Verify' : 'Install'),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filledTonal(
                tooltip: 'Reset rootfs',
                onPressed: busy ? null : onReset,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppTheme.cyan, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppTheme.textTertiary,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PackageProfileRow extends StatelessWidget {
  const _PackageProfileRow({
    required this.label,
    required this.packages,
    required this.status,
    required this.installed,
    required this.enabled,
    required this.downloadMb,
    required this.installedMb,
    required this.onPreview,
    required this.onInstall,
    this.recoveryHint,
  });

  final String label;
  final List<String> packages;
  final String status;
  final bool installed;
  final bool enabled;
  final double downloadMb;
  final double installedMb;
  final String? recoveryHint;
  final VoidCallback onPreview;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated.withOpacity(0.72),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border.withOpacity(0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    _Pill(label: status),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  packages.isEmpty
                      ? 'busybox, shell, apk'
                      : packages.join(', '),
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 6),
                Text(
                  '${downloadMb.toStringAsFixed(1)} MB download · '
                  '${installedMb.toStringAsFixed(1)} MB installed'
                  '${recoveryHint == null ? '' : ' · $recoveryHint'}',
                  style: const TextStyle(
                    color: AppTheme.textTertiary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Preview install evidence',
                onPressed: onPreview,
                icon: const Icon(Icons.visibility_outlined),
                color: AppTheme.textSecondary,
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 34,
                child: FilledButton.tonalIcon(
                  key: ValueKey('linuxSandbox.installProfile.$label'),
                  onPressed: !enabled || installed ? null : onInstall,
                  icon: Icon(
                    installed
                        ? Icons.check_circle_outline
                        : Icons.download_outlined,
                    size: 16,
                  ),
                  label: Text(installed ? '已安装' : '安装'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.cyan.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.cyan.withOpacity(0.22)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.ready});

  final bool ready;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: ready ? AppTheme.success : AppTheme.warning,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color:
                (ready ? AppTheme.success : AppTheme.warning).withOpacity(0.28),
            blurRadius: 10,
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(color: AppTheme.textTertiary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
