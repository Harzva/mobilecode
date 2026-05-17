// lib/providers/skill_provider.dart
// Skill Provider - Riverpod providers for skill state management
// 技能管理 Riverpod 状态管理

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/skill_model.dart';
import '../services/skill_manager_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Service Provider
// ═══════════════════════════════════════════════════════════════════════════

/// Global provider for the [SkillManagerService] instance.
///
/// Usage:
/// ```dart
/// final service = ref.read(skillManagerServiceProvider);
/// final skills = ref.watch(allSkillsProvider);
/// ```
final skillManagerServiceProvider = Provider<SkillManagerService>((ref) {
  final service = SkillManagerService.instance;

  // Listen to ChangeNotifier and invalidate downstream providers
  service.addListener(() {
    ref.invalidate(allSkillsProvider);
    ref.invalidate(installedSkillsProvider);
    ref.invalidate(enabledSkillsProvider);
    ref.invalidate(mcpServersProvider);
    ref.invalidate(skillStatsProvider);
  });

  return service;
});

/// Initialize the skill manager service.
///
/// Call this once at app startup:
/// ```dart
/// await ref.read(skillInitProvider.future);
/// ```
final skillInitProvider = FutureProvider<void>((ref) async {
  final service = ref.read(skillManagerServiceProvider);
  await service.initialize();
});

// ═══════════════════════════════════════════════════════════════════════════
// Skill State Providers
// ═══════════════════════════════════════════════════════════════════════════

/// All registered skills (installed + available).
final allSkillsProvider = Provider<List<Skill>>((ref) {
  final service = ref.watch(skillManagerServiceProvider);
  service.isInitialized; // Access to trigger watch on re-init
  return service.allSkills;
});

/// Currently installed skills only.
final installedSkillsProvider = Provider<List<Skill>>((ref) {
  final service = ref.watch(skillManagerServiceProvider);
  return service.installedSkills;
});

/// Currently enabled skills only.
final enabledSkillsProvider = Provider<List<Skill>>((ref) {
  final service = ref.watch(skillManagerServiceProvider);
  return service.enabledSkills;
});

/// Built-in skills.
final builtInSkillsProvider = Provider<List<Skill>>((ref) {
  final service = ref.watch(skillManagerServiceProvider);
  return service.getBuiltInSkills();
});

/// Available (not yet installed) skills.
final availableSkillsProvider = FutureProvider<List<Skill>>((ref) async {
  final service = ref.watch(skillManagerServiceProvider);
  return service.getAvailableSkills();
});

// ═══════════════════════════════════════════════════════════════════════════
// Individual Skill Provider
// ═══════════════════════════════════════════════════════════════════════════

/// Provider family for a specific skill by ID.
///
/// Usage:
/// ```dart
/// final skill = ref.watch(skillByIdProvider('flutter_dev'));
/// ```
final skillByIdProvider = Provider.family<Skill?, String>((ref, skillId) {
  final service = ref.watch(skillManagerServiceProvider);
  return service.getSkill(skillId);
});

/// Whether a specific skill is enabled.
final skillEnabledProvider = Provider.family<bool, String>((ref, skillId) {
  final service = ref.watch(skillManagerServiceProvider);
  return service.getSkill(skillId)?.isEnabled ?? false;
});

/// Whether a specific skill is installed.
final skillInstalledProvider = Provider.family<bool, String>((ref, skillId) {
  final service = ref.watch(skillManagerServiceProvider);
  return service.getSkill(skillId)?.isInstalled ?? false;
});

/// MCP servers associated with a specific skill.
final skillMcpServersProvider = Provider.family<List<McpServer>, String>((ref, skillId) {
  final service = ref.watch(skillManagerServiceProvider);
  return service.getMcpServersForSkill(skillId);
});

// ═══════════════════════════════════════════════════════════════════════════
// MCP Server Providers
// ═══════════════════════════════════════════════════════════════════════════

/// All MCP servers.
final mcpServersProvider = Provider<List<McpServer>>((ref) {
  final service = ref.watch(skillManagerServiceProvider);
  return service.allMcpServers;
});

/// Running MCP servers only.
final runningMcpServersProvider = Provider<List<McpServer>>((ref) {
  final servers = ref.watch(mcpServersProvider);
  return servers.where((s) => s.isRunning).toList();
});

/// Provider family for a specific MCP server by ID.
final mcpServerByIdProvider = Provider.family<McpServer?, String>((ref, serverId) {
  final service = ref.watch(skillManagerServiceProvider);
  return service.getMcpServer(serverId);
});

/// Whether a specific MCP server is enabled.
final mcpServerEnabledProvider = Provider.family<bool, String>((ref, serverId) {
  final service = ref.watch(skillManagerServiceProvider);
  return service.getMcpServer(serverId)?.isEnabled ?? false;
});

/// Whether a specific MCP server is running.
final mcpServerRunningProvider = Provider.family<bool, String>((ref, serverId) {
  final service = ref.watch(skillManagerServiceProvider);
  return service.getMcpServer(serverId)?.isRunning ?? false;
});

/// MCP server status.
final mcpServerStatusProvider = Provider.family<McpServerStatus, String>((ref, serverId) {
  final service = ref.watch(skillManagerServiceProvider);
  return service.getMcpServer(serverId)?.status ?? McpServerStatus.stopped;
});

// ═══════════════════════════════════════════════════════════════════════════
// Async Action Providers
// ═══════════════════════════════════════════════════════════════════════════

/// Async provider for searching skills.
final skillSearchProvider = FutureProvider.family<List<Skill>, String>((ref, query) async {
  if (query.trim().isEmpty) return [];
  final service = ref.read(skillManagerServiceProvider);
  return service.searchSkills(query.trim());
});

/// Async provider for searching GitHub skills.
final githubSkillSearchProvider = FutureProvider.family<List<Skill>, ({String? query, String language})>(
  (ref, params) async {
    final service = ref.read(skillManagerServiceProvider);
    return service.searchGitHubSkills(query: params.query, language: params.language);
  },
);

/// Async provider for trending GitHub skills.
final trendingSkillsProvider = FutureProvider<List<Skill>>((ref) async {
  final service = ref.read(skillManagerServiceProvider);
  return service.getTrendingSkills();
});

/// Async provider for checking skill updates.
final skillUpdateCheckProvider = FutureProvider.family<Skill?, String>((ref, skillId) async {
  final service = ref.read(skillManagerServiceProvider);
  return service.checkUpdate(skillId);
});

/// Async provider for importing from GitHub.
final importFromGitHubProvider =
    FutureProvider.family<Skill, String>((ref, githubUrl) async {
  final service = ref.read(skillManagerServiceProvider);
  return service.importFromGitHub(githubUrl);
});

// ═══════════════════════════════════════════════════════════════════════════
// Stats Provider
// ═══════════════════════════════════════════════════════════════════════════

/// Aggregated statistics about skills and MCP servers.
final skillStatsProvider = Provider<SkillStats>((ref) {
  final allSkills = ref.watch(allSkillsProvider);
  final installed = ref.watch(installedSkillsProvider);
  final enabled = ref.watch(enabledSkillsProvider);
  final mcpServers = ref.watch(mcpServersProvider);

  return SkillStats(
    totalSkills: allSkills.length,
    installedSkills: installed.length,
    enabledSkills: enabled.length,
    totalMcpServers: mcpServers.length,
    runningMcpServers: mcpServers.where((s) => s.isRunning).length,
    totalActions: allSkills.fold(0, (sum, s) => sum + s.actions.length),
    totalPrompts: allSkills.fold(0, (sum, s) => sum + s.prompts.length),
  );
});

/// Statistics container for skill system overview.
class SkillStats {
  final int totalSkills;
  final int installedSkills;
  final int enabledSkills;
  final int totalMcpServers;
  final int runningMcpServers;
  final int totalActions;
  final int totalPrompts;

  const SkillStats({
    required this.totalSkills,
    required this.installedSkills,
    required this.enabledSkills,
    required this.totalMcpServers,
    required this.runningMcpServers,
    required this.totalActions,
    required this.totalPrompts,
  });

  /// Number of available (not installed) skills.
  int get availableSkills => totalSkills - installedSkills;

  /// Number of stopped MCP servers.
  int get stoppedMcpServers => totalMcpServers - runningMcpServers;

  @override
  String toString() {
    return 'SkillStats(skills: $totalSkills, installed: $installedSkills, '
        'enabled: $enabledSkills, mcp: $totalMcpServers/$runningMcpServers running)';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// UI State Providers (mutable state for UI)
// ═══════════════════════════════════════════════════════════════════════════

/// Currently selected skill tab index.
/// 0 = 已安装 (Installed)
/// 1 = 发现 (Discover)
/// 2 = MCP管理 (MCP)
final skillTabIndexProvider = StateProvider<int>((ref) => 0);

/// Search query for skill discovery.
final skillSearchQueryProvider = StateProvider<String>((ref) => '');

/// Selected tag filter.
final skillTagFilterProvider = StateProvider<String?>((ref) => null);

/// Whether the GitHub import bottom sheet is visible.
final githubImportVisibleProvider = StateProvider<bool>((ref) => false);

/// Loading state for async operations.
final skillLoadingProvider = StateProvider<String?>((ref) => null);

/// Selected skill ID for detail view.
final selectedSkillIdProvider = StateProvider<String?>((ref) => null);

/// Selected MCP server ID for detail view.
final selectedMcpServerIdProvider = StateProvider<String?>((ref) => null);

// ═══════════════════════════════════════════════════════════════════════════
// Notifier Providers (for complex state mutations)
// ═══════════════════════════════════════════════════════════════════════════

/// Notifier for managing skill lifecycle operations.
class SkillLifecycleNotifier extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() async {
    // No initial state needed
  }

  SkillManagerService get _service => ref.read(skillManagerServiceProvider);

  /// Install a skill.
  Future<void> install(Skill skill) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _service.install(skill));
  }

  /// Uninstall a skill.
  Future<void> uninstall(String skillId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _service.uninstall(skillId));
  }

  /// Toggle skill enable state.
  Future<void> toggle(String skillId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _service.toggle(skillId));
  }

  /// Enable a skill.
  Future<void> enable(String skillId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _service.enable(skillId));
  }

  /// Disable a skill.
  Future<void> disable(String skillId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _service.disable(skillId));
  }

  /// Update a skill.
  Future<void> updateSkill(String skillId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _service.update(skillId));
  }

  /// Import from GitHub.
  Future<Skill> importFromGitHub(String url) async {
    state = const AsyncValue.loading();
    final result = await AsyncValue.guard(() => _service.importFromGitHub(url));
    state = result;
    if (result.hasError) throw result.error!;
    return result.value! as Skill;
  }
}

final skillLifecycleProvider =
    AsyncNotifierProvider<SkillLifecycleNotifier, void>(SkillLifecycleNotifier.new);

/// Notifier for MCP server operations.
class McpServerNotifier extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() async {
    // No initial state needed
  }

  SkillManagerService get _service => ref.read(skillManagerServiceProvider);

  /// Enable an MCP server.
  Future<void> enable(String serverId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _service.enableMcpServer(serverId));
  }

  /// Disable an MCP server.
  Future<void> disable(String serverId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _service.disableMcpServer(serverId));
  }

  /// Toggle an MCP server.
  Future<void> toggle(String serverId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _service.toggleMcpServer(serverId));
  }

  /// Add a custom MCP server.
  Future<void> addCustom(McpServer server) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _service.addCustomMcpServer(server));
  }

  /// Remove an MCP server.
  Future<void> remove(String serverId) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _service.removeMcpServer(serverId));
  }
}

final mcpServerLifecycleProvider =
    AsyncNotifierProvider<McpServerNotifier, void>(McpServerNotifier.new);
