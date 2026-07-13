import 'cli_hub_catalog_service.dart';
import 'runtime_provider.dart';

enum CapabilitySurfaceType {
  runtimeProvider,
  integrationProvider,
  cliExtensionProvider,
}

enum CapabilityState {
  installed,
  available,
  authenticated,
  needsSetup,
  blocked,
  error,
}

class CapabilityBoundary {
  const CapabilityBoundary({
    required this.runtimeStoresAccountTokens,
    required this.integrationExecutesShell,
    required this.cliHubAllowsRawShell,
    required this.termuxDefaultRuntime,
  });

  final bool runtimeStoresAccountTokens;
  final bool integrationExecutesShell;
  final bool cliHubAllowsRawShell;
  final bool termuxDefaultRuntime;

  bool get safe =>
      !runtimeStoresAccountTokens &&
      !integrationExecutesShell &&
      !cliHubAllowsRawShell &&
      !termuxDefaultRuntime;
}

class CapabilitySurfaceDescriptor {
  const CapabilitySurfaceDescriptor({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.type,
    required this.state,
    required this.boundary,
    required this.riskLevel,
    required this.credentialPolicy,
    required this.requiresApproval,
    this.runtimeProviderType,
    this.installProfile,
    this.probeTaskKind,
    this.authTaskKind,
    this.readOnlyTaskKinds = const [],
    this.mutationTaskKinds = const [],
  });

  final String id;
  final String title;
  final String subtitle;
  final CapabilitySurfaceType type;
  final CapabilityState state;
  final CapabilityBoundary boundary;
  final CliHubRiskLevel riskLevel;
  final CliHubCredentialPolicy credentialPolicy;
  final bool requiresApproval;
  final RuntimeProviderType? runtimeProviderType;
  final String? installProfile;
  final String? probeTaskKind;
  final String? authTaskKind;
  final List<String> readOnlyTaskKinds;
  final List<String> mutationTaskKinds;
}

abstract interface class IntegrationProvider {
  String get id;
  CapabilityState get state;
  CliHubCredentialPolicy get credentialPolicy;
}

abstract interface class CliExtensionProvider {
  String get id;
  String? get installProfile;
  String? get probeTaskKind;
  CliHubRiskLevel get riskLevel;
  CliHubCredentialPolicy get credentialPolicy;
}

class CapabilitySurfaceService {
  const CapabilitySurfaceService();

  static const runtimeBoundary = CapabilityBoundary(
    runtimeStoresAccountTokens: false,
    integrationExecutesShell: false,
    cliHubAllowsRawShell: false,
    termuxDefaultRuntime: false,
  );

  static const integrationBoundary = CapabilityBoundary(
    runtimeStoresAccountTokens: false,
    integrationExecutesShell: false,
    cliHubAllowsRawShell: false,
    termuxDefaultRuntime: false,
  );

  static const cliExtensionBoundary = CapabilityBoundary(
    runtimeStoresAccountTokens: false,
    integrationExecutesShell: false,
    cliHubAllowsRawShell: false,
    termuxDefaultRuntime: false,
  );

  List<CapabilitySurfaceDescriptor> runtimeSurfaces({
    bool alpineInstalled = false,
  }) {
    return [
      const CapabilitySurfaceDescriptor(
        id: 'native-helper',
        title: 'Native Helper',
        subtitle: '默认本地 runtime：Git、文件、preflight、Flutter 构建、APK 安装和 evidence。',
        type: CapabilitySurfaceType.runtimeProvider,
        state: CapabilityState.available,
        boundary: runtimeBoundary,
        riskLevel: CliHubRiskLevel.medium,
        credentialPolicy: CliHubCredentialPolicy.none,
        requiresApproval: true,
        runtimeProviderType: RuntimeProviderType.mobileCodeHelper,
        readOnlyTaskKinds: ['project_preflight', 'task_logs'],
        mutationTaskKinds: [
          'git_clone',
          'flutter_analyze',
          'flutter_test',
          'flutter_build_apk',
          'apk_install',
          'apk_launch',
        ],
      ),
      CapabilitySurfaceDescriptor(
        id: 'alpine-linux-sandbox',
        title: 'Alpine Linux Sandbox',
        subtitle:
            'App-owned rootfs + package profiles；CLI Hub 只通过 typed tasks 运行。',
        type: CapabilitySurfaceType.runtimeProvider,
        state: alpineInstalled
            ? CapabilityState.available
            : CapabilityState.needsSetup,
        boundary: runtimeBoundary,
        riskLevel: CliHubRiskLevel.medium,
        credentialPolicy: CliHubCredentialPolicy.none,
        requiresApproval: true,
        runtimeProviderType: RuntimeProviderType.linuxSandbox,
        readOnlyTaskKinds: ['apk_version', 'git_version', 'node_version'],
        mutationTaskKinds: ['rootfs_install', 'package_install', 'npm_build'],
      ),
      CapabilitySurfaceDescriptor(
        id: 'embedded-lite',
        title: 'Embedded Lite',
        subtitle: 'WebView/内置轻量体验，用于基础交互和离线降级。',
        type: CapabilitySurfaceType.runtimeProvider,
        state: CapabilityState.available,
        boundary: runtimeBoundary,
        riskLevel: CliHubRiskLevel.low,
        credentialPolicy: CliHubCredentialPolicy.none,
        requiresApproval: false,
        runtimeProviderType: RuntimeProviderType.embeddedLite,
        readOnlyTaskKinds: ['local_preview'],
      ),
      CapabilitySurfaceDescriptor(
        id: 'termux-fallback',
        title: 'Termux fallback',
        subtitle: '只作为高级 fallback；默认内置路径优先，不要求登录或 CLI 依赖 Termux。',
        type: CapabilitySurfaceType.runtimeProvider,
        state: CapabilityState.blocked,
        boundary: runtimeBoundary,
        riskLevel: CliHubRiskLevel.high,
        credentialPolicy: CliHubCredentialPolicy.external,
        requiresApproval: true,
        runtimeProviderType: RuntimeProviderType.externalTermux,
        mutationTaskKinds: ['external_handoff'],
      ),
    ];
  }

  List<CapabilitySurfaceDescriptor> integrationSurfaces() {
    return const [
      CapabilitySurfaceDescriptor(
        id: 'chatgpt-codex',
        title: 'ChatGPT / Codex',
        subtitle: '官方 browser/OAuth 登录；凭据只进 Credential Vault。',
        type: CapabilitySurfaceType.integrationProvider,
        state: CapabilityState.needsSetup,
        boundary: integrationBoundary,
        riskLevel: CliHubRiskLevel.high,
        credentialPolicy: CliHubCredentialPolicy.officialBrowser,
        requiresApproval: true,
        authTaskKind: 'openai_official_login',
        readOnlyTaskKinds: ['quota_refresh'],
        mutationTaskKinds: ['model_forward'],
      ),
      CapabilitySurfaceDescriptor(
        id: 'claude',
        title: 'Claude',
        subtitle: '官方账号登录；Usage Hub 负责额度读取和错误恢复。',
        type: CapabilitySurfaceType.integrationProvider,
        state: CapabilityState.needsSetup,
        boundary: integrationBoundary,
        riskLevel: CliHubRiskLevel.high,
        credentialPolicy: CliHubCredentialPolicy.officialBrowser,
        requiresApproval: true,
        authTaskKind: 'claude_official_login',
        readOnlyTaskKinds: ['quota_refresh'],
        mutationTaskKinds: ['model_forward'],
      ),
      CapabilitySurfaceDescriptor(
        id: 'github-copilot',
        title: 'GitHub / Copilot',
        subtitle: '与现有 GitHub auth surface 统一；Copilot 转发走 ProviderAdapter。',
        type: CapabilitySurfaceType.integrationProvider,
        state: CapabilityState.needsSetup,
        boundary: integrationBoundary,
        riskLevel: CliHubRiskLevel.high,
        credentialPolicy: CliHubCredentialPolicy.secureStorage,
        requiresApproval: true,
        authTaskKind: 'github_official_login',
        readOnlyTaskKinds: ['quota_refresh', 'auth_status'],
        mutationTaskKinds: ['model_forward'],
      ),
      CapabilitySurfaceDescriptor(
        id: 'google-antigravity',
        title: 'Google / Antigravity',
        subtitle: '官方 Google 账号登录；Google Workspace CLI 复用同一账号边界。',
        type: CapabilitySurfaceType.integrationProvider,
        state: CapabilityState.needsSetup,
        boundary: integrationBoundary,
        riskLevel: CliHubRiskLevel.high,
        credentialPolicy: CliHubCredentialPolicy.officialBrowser,
        requiresApproval: true,
        authTaskKind: 'google_official_login',
        readOnlyTaskKinds: ['quota_refresh', 'auth_status'],
        mutationTaskKinds: ['model_forward'],
      ),
    ];
  }

  CapabilitySurfaceDescriptor cliExtensionSurface(CliHubEntry entry) {
    return CapabilitySurfaceDescriptor(
      id: entry.id,
      title: entry.title,
      subtitle:
          '${entry.command} · ${entry.install.strategy.name} · ${entry.supportLevel.name}',
      type: CapabilitySurfaceType.cliExtensionProvider,
      state: entry.supportLevel == CliHubSupportLevel.planned
          ? CapabilityState.needsSetup
          : CapabilityState.installed,
      boundary: cliExtensionBoundary,
      riskLevel: entry.riskLevel,
      credentialPolicy: entry.credentialPolicy,
      requiresApproval: entry.tasks.any((task) => task.requiresApproval),
      installProfile: entry.install.profileId,
      probeTaskKind: entry.probe.taskKind,
      authTaskKind: entry.auth.required ? _firstAuthTaskKind(entry) : null,
      readOnlyTaskKinds: _taskKinds(entry, entry.readOnlyTaskIds),
      mutationTaskKinds: _taskKinds(entry, entry.mutationTaskIds),
    );
  }
}

List<String> _taskKinds(CliHubEntry entry, List<String> ids) {
  final byId = {for (final task in entry.tasks) task.id: task.taskKind};
  return ids.map((id) => byId[id]).whereType<String>().toList(growable: false);
}

String? _firstAuthTaskKind(CliHubEntry entry) {
  for (final task in entry.tasks) {
    if (task.taskKind.contains('_auth_')) return task.taskKind;
  }
  return null;
}
