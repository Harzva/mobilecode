// lib/services/skill_manager_service.dart
// Skill Manager Service - Full lifecycle skill management + MCP server management
// 技能管理与MCP服务器管理服务

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/skill_model.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Exceptions
// ═══════════════════════════════════════════════════════════════════════════

class SkillException implements Exception {
  final String message;
  final String? skillId;
  SkillException(this.message, {this.skillId});
  @override
  String toString() => 'SkillException[$skillId]: $message';
}

class SkillNotFoundException extends SkillException {
  SkillNotFoundException(String skillId) : super('Skill not found', skillId: skillId);
}

class SkillAlreadyInstalledException extends SkillException {
  SkillAlreadyInstalledException(String skillId) : super('Skill already installed', skillId: skillId);
}

class McpServerException implements Exception {
  final String message;
  final String? serverId;
  McpServerException(this.message, {this.serverId});
  @override
  String toString() => 'McpServerException[$serverId]: $message';
}

// ═══════════════════════════════════════════════════════════════════════════
// Skill Manager Service
// ═══════════════════════════════════════════════════════════════════════════

/// Manages the full lifecycle of Skills and MCP Servers.
///
/// ## Skill Lifecycle
/// Discovery (built-in + GitHub marketplace)
///    -> Import (GitHub one-click / local ZIP / URL)
///    -> Installation
///    -> Enable/Disable
///    -> Update
///    -> Uninstall
///
/// ## MCP Server Management
/// Register MCP servers from skills
///    -> Enable/Disable
///    -> Monitor status
class SkillManagerService extends ChangeNotifier {
  // ── Singleton ──────────────────────────────────

  static SkillManagerService? _instance;
  static SkillManagerService get instance => _instance ??= SkillManagerService._internal();
  static void reset() => _instance = null;

  SkillManagerService._internal();

  factory SkillManagerService() => instance;

  // ── Storage Keys ───────────────────────────────

  static const String _skillsKey = 'skill_manager_installed_skills';
  static const String _mcpServersKey = 'skill_manager_mcp_servers';
  static const String _logsKey = 'skill_manager_install_logs';
  static const String _enabledSkillsKey = 'skill_manager_enabled_skills';

  // ── Internal State ─────────────────────────────

  SharedPreferences? _prefs;
  final Map<String, Skill> _skills = {};
  final Map<String, McpServer> _mcpServers = {};
  final List<SkillInstallLog> _logs = [];
  final List<Skill> _builtInSkills = [];
  bool _initialized = false;

  // ── Public Getters ─────────────────────────────

  bool get isInitialized => _initialized;

  /// All registered skills (both installed and built-in).
  List<Skill> get allSkills => List.unmodifiable(_skills.values);

  /// Currently installed skills.
  List<Skill> get installedSkills =>
      List.unmodifiable(_skills.values.where((s) => s.isInstalled));

  /// Enabled skills.
  List<Skill> get enabledSkills =>
      List.unmodifiable(_skills.values.where((s) => s.isEnabled));

  /// All MCP servers.
  List<McpServer> get allMcpServers => List.unmodifiable(_mcpServers.values);

  /// Installation logs.
  List<SkillInstallLog> get logs => List.unmodifiable(_logs);

  // ── Initialization ─────────────────────────────

  /// Initialize the service: load persisted skills, MCP servers, and logs.
  Future<void> initialize() async {
    if (_initialized) return;

    debugPrint('[SkillManager] Initializing...');

    _prefs = await SharedPreferences.getInstance();

    // Register built-in skills first
    _registerBuiltInSkills();

    // Load persisted installed skills
    await _loadPersistedSkills();

    // Load persisted MCP servers
    await _loadPersistedMcpServers();

    // Load persisted logs
    await _loadPersistedLogs();

    _initialized = true;
    debugPrint('[SkillManager] Initialized: ${_skills.length} skills, ${_mcpServers.length} MCP servers');
    notifyListeners();
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('SkillManagerService not initialized. Call initialize() first.');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Skill Discovery
  // ═══════════════════════════════════════════════════════════════════════

  /// Get built-in skills (pre-bundled with the app).
  List<Skill> getBuiltInSkills() {
    _ensureInitialized();
    return List.unmodifiable(_builtInSkills);
  }

  /// Get skills filtered by installation status.
  List<Skill> getSkillsByInstallStatus({required bool installed}) {
    _ensureInitialized();
    return List.unmodifiable(_skills.values.where((s) => s.isInstalled == installed));
  }

  /// Get a skill by its ID.
  Skill? getSkill(String id) {
    _ensureInitialized();
    return _skills[id];
  }

  /// Search skills by query (matches name, description, tags, author).
  Future<List<Skill>> searchSkills(String query) async {
    _ensureInitialized();
    final lowerQuery = query.toLowerCase();
    return List.unmodifiable(
      _skills.values.where((skill) {
        return skill.name.toLowerCase().contains(lowerQuery) ||
            skill.description.toLowerCase().contains(lowerQuery) ||
            skill.author.toLowerCase().contains(lowerQuery) ||
            skill.tags.any((t) => t.toLowerCase().contains(lowerQuery)) ||
            skill.actions.any((a) => a.toLowerCase().contains(lowerQuery));
      }),
    );
  }

  /// Get skills filtered by a specific tag.
  List<Skill> getSkillsByTag(String tag) {
    _ensureInitialized();
    final lowerTag = tag.toLowerCase();
    return List.unmodifiable(
      _skills.values.where((s) => s.tags.any((t) => t.toLowerCase() == lowerTag)),
    );
  }

  /// Get available skills that are not yet installed.
  Future<List<Skill>> getAvailableSkills() async {
    _ensureInitialized();
    return getSkillsByInstallStatus(installed: false);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // GitHub Skill Discovery
  // ═══════════════════════════════════════════════════════════════════════

  /// Search GitHub for repositories tagged as mobilecode skills.
  ///
  /// Uses GitHub search API to find repositories with topic "mobilecode-skill".
  Future<List<Skill>> searchGitHubSkills({String? query, String language = ''}) async {
    _ensureInitialized();

    try {
      final q = StringBuffer('topic:mobilecode-skill');
      if (query != null && query.isNotEmpty) {
        q.write(' $query');
      }
      if (language.isNotEmpty) {
        q.write(' language:$language');
      }

      final uri = Uri.https(
        'api.github.com',
        '/search/repositories',
        {'q': q.toString(), 'sort': 'stars', 'order': 'desc', 'per_page': '30'},
      );

      debugPrint('[SkillManager] Searching GitHub: ${uri.toString()}');
      final response = await http.get(uri);

      if (response.statusCode != 200) {
        throw SkillException('GitHub API error: ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final items = data['items'] as List<dynamic>? ?? [];

      final results = <Skill>[];
      for (final item in items) {
        final repo = item as Map<String, dynamic>;
        final fullName = repo['full_name'] as String? ?? '';
        final stars = repo['stargazers_count'] as int? ?? 0;

        // Construct a Skill from GitHub repo metadata
        // (Detailed skill.yaml will be fetched during import)
        final skill = Skill(
          id: fullName.replaceAll('/', '_'),
          name: repo['name'] as String? ?? 'Unknown',
          version: '1.0.0',
          description: repo['description'] as String? ?? 'No description',
          author: fullName.split('/').first,
          tags: ['github', ...(repo['topics'] as List<dynamic>?)?.cast<String>() ?? []],
          actions: const [],
          prompts: const [],
          mcpServers: const [],
          source: SkillSource.github,
          githubUrl: repo['html_url'] as String?,
          rating: 0.0,
          installCount: stars,
        );
        results.add(skill);
      }

      debugPrint('[SkillManager] Found ${results.length} skills on GitHub');
      return results;
    } catch (e) {
      debugPrint('[SkillManager] GitHub search failed: $e');
      // Return demo data if API fails
      return _getDemoGitHubSkills();
    }
  }

  /// Get trending/popular skills from GitHub.
  Future<List<Skill>> getTrendingSkills() async {
    return searchGitHubSkills(query: 'stars:>5');
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Import
  // ═══════════════════════════════════════════════════════════════════════

  /// Import a skill from a GitHub repository URL.
  ///
  /// Flow:
  /// 1. Parse the GitHub URL
  /// 2. Fetch skill.yaml from the repo's default branch
  /// 3. Parse the manifest into a Skill object
  /// 4. Return the skill for preview before installation
  Future<Skill> importFromGitHub(String githubUrl) async {
    _ensureInitialized();
    debugPrint('[SkillManager] Importing from GitHub: $githubUrl');

    try {
      // Parse URL: https://github.com/user/repo -> raw.githubusercontent.com
      final parsed = Uri.parse(githubUrl);
      final segments = parsed.pathSegments;
      if (segments.length < 2) {
        throw SkillException('Invalid GitHub URL: $githubUrl');
      }

      final owner = segments[0];
      final repo = segments[1];

      // Try to fetch skill.yaml from main branch first, then master
      String? yamlContent;
      for (final branch in ['main', 'master']) {
        final rawUri = Uri.https(
          'raw.githubusercontent.com',
          '/$owner/$repo/$branch/skill.yaml',
        );
        final response = await http.get(rawUri);
        if (response.statusCode == 200) {
          yamlContent = response.body;
          break;
        }
      }

      // Fallback: try skill.yml
      yamlContent ??= await _tryFetchYamlAlternate(owner, repo);

      if (yamlContent == null) {
        // If no skill.yaml found, create a skill from repo metadata
        return _skillFromGitHubMetadata(githubUrl, owner, repo);
      }

      // Parse YAML content (simplified YAML-like parsing)
      final manifest = _parseYamlLike(yamlContent);
      final skill = Skill.fromManifest(
        manifest,
        source: SkillSource.github,
        githubUrl: githubUrl,
      );

      // Store in registry (not installed yet)
      _skills[skill.id] = skill;
      notifyListeners();

      debugPrint('[SkillManager] Imported skill: ${skill.id}');
      return skill;
    } catch (e) {
      debugPrint('[SkillManager] GitHub import failed: $e');
      throw SkillException('Failed to import from GitHub: $e');
    }
  }

  /// Import from a local ZIP file path.
  Future<Skill> importFromZip(String zipPath) async {
    _ensureInitialized();
    debugPrint('[SkillManager] Importing from ZIP: $zipPath');

    try {
      final file = File(zipPath);
      if (!await file.exists()) {
        throw SkillException('ZIP file not found: $zipPath');
      }

      // Extract to temp directory and parse skill.yaml
      final appDir = await getApplicationDocumentsDirectory();
      final extractDir = Directory(path.join(appDir.path, 'skills', '_temp_${DateTime.now().millisecondsSinceEpoch}'));
      await extractDir.create(recursive: true);

      // TODO: Implement ZIP extraction (using archive package)
      // For now, look for skill.yaml in the same directory
      final skillYamlFile = File(path.join(file.parent.path, 'skill.yaml'));
      if (!await skillYamlFile.exists()) {
        throw SkillException('skill.yaml not found in ZIP');
      }

      final content = await skillYamlFile.readAsString();
      final manifest = _parseYamlLike(content);
      final skill = Skill.fromManifest(
        manifest,
        source: SkillSource.local,
        localPath: extractDir.path,
      );

      _skills[skill.id] = skill;
      notifyListeners();

      return skill;
    } catch (e) {
      throw SkillException('Failed to import from ZIP: $e');
    }
  }

  /// Import from a generic URL.
  Future<Skill> importFromUrl(String url) async {
    _ensureInitialized();
    debugPrint('[SkillManager] Importing from URL: $url');

    try {
      final uri = Uri.parse(url);
      final response = await http.get(uri);

      if (response.statusCode != 200) {
        throw SkillException('HTTP ${response.statusCode}');
      }

      final manifest = _parseYamlLike(response.body);
      final skill = Skill.fromManifest(
        manifest,
        source: SkillSource.local,
      );

      _skills[skill.id] = skill;
      notifyListeners();

      return skill;
    } catch (e) {
      throw SkillException('Failed to import from URL: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Install / Uninstall / Update
  // ═══════════════════════════════════════════════════════════════════════

  /// Install a skill: mark as installed, register MCP servers, persist.
  Future<void> install(Skill skill) async {
    _ensureInitialized();

    if (_skills[skill.id]?.isInstalled ?? false) {
      throw SkillAlreadyInstalledException(skill.id);
    }

    debugPrint('[SkillManager] Installing skill: ${skill.id}');

    // Mark as installed
    final installed = skill.copyWith(
      isInstalled: true,
      installedAt: DateTime.now(),
    );
    _skills[skill.id] = installed;

    // Register MCP servers from this skill
    if (skill.hasMcpServers) {
      await registerMcpServers(skill.id);
    }

    // Persist
    await _persistSkills();
    _addLog(skill.id, 'install', true);

    notifyListeners();
    debugPrint('[SkillManager] Installed: ${skill.id}');
  }

  /// Uninstall a skill: remove files, unregister MCP, mark as uninstalled.
  Future<void> uninstall(String skillId) async {
    _ensureInitialized();

    final skill = _skills[skillId];
    if (skill == null) throw SkillNotFoundException(skillId);

    debugPrint('[SkillManager] Uninstalling skill: $skillId');

    // Disable first if enabled
    if (skill.isEnabled) {
      await disable(skillId);
    }

    // Unregister associated MCP servers
    if (skill.hasMcpServers) {
      await _unregisterMcpServersForSkill(skillId);
    }

    // Remove local files if not built-in
    if (skill.localPath != null && skill.source != SkillSource.builtIn) {
      try {
        final dir = Directory(skill.localPath!);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      } catch (e) {
        debugPrint('[SkillManager] Failed to delete skill dir: $e');
      }
    }

    // Mark as uninstalled (keep in registry for potential re-enable)
    _skills[skillId] = skill.copyWith(
      isInstalled: false,
      isEnabled: false,
      installedAt: null,
    );

    // Remove from registry if not built-in and not from GitHub
    if (skill.source != SkillSource.builtIn && skill.source != SkillSource.github) {
      _skills.remove(skillId);
    }

    await _persistSkills();
    _addLog(skillId, 'uninstall', true);

    notifyListeners();
    debugPrint('[SkillManager] Uninstalled: $skillId');
  }

  /// Check if there's an update available for a skill.
  Future<Skill?> checkUpdate(String skillId) async {
    _ensureInitialized();

    final skill = _skills[skillId];
    if (skill == null) return null;
    if (skill.source != SkillSource.github || skill.githubUrl == null) return null;

    try {
      // Fetch latest skill.yaml from GitHub
      final latest = await importFromGitHub(skill.githubUrl!);

      // Simple version comparison (assuming semver)
      if (_isNewerVersion(latest.version, skill.version)) {
        return latest;
      }
      return null;
    } catch (e) {
      debugPrint('[SkillManager] Update check failed: $e');
      return null;
    }
  }

  /// Apply an update: reinstall the skill with the latest version.
  Future<void> update(String skillId) async {
    _ensureInitialized();

    final skill = _skills[skillId];
    if (skill == null) throw SkillNotFoundException(skillId);

    debugPrint('[SkillManager] Updating skill: $skillId');

    // Re-import from source
    Skill? updated;
    if (skill.githubUrl != null) {
      updated = await importFromGitHub(skill.githubUrl!);
    } else if (skill.localPath != null) {
      // Re-read local skill.yaml
      final yamlFile = File('${skill.localPath}/skill.yaml');
      if (await yamlFile.exists()) {
        final content = await yamlFile.readAsString();
        updated = Skill.fromManifest(
          _parseYamlLike(content),
          source: skill.source,
          localPath: skill.localPath,
        );
      }
    }

    if (updated == null) {
      throw SkillException('Cannot determine update source', skillId: skillId);
    }

    // Preserve installation state
    _skills[skillId] = updated.copyWith(
      isInstalled: true,
      isEnabled: skill.isEnabled,
      installedAt: skill.installedAt,
      usageCount: skill.usageCount,
    );

    // Re-register MCP servers
    if (updated.hasMcpServers) {
      await registerMcpServers(skillId);
    }

    await _persistSkills();
    _addLog(skillId, 'update', true);

    notifyListeners();
    debugPrint('[SkillManager] Updated: $skillId to v${updated.version}');
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Enable / Disable
  // ═══════════════════════════════════════════════════════════════════════

  /// Enable a skill: activate its actions and prompt templates.
  Future<void> enable(String skillId) async {
    _ensureInitialized();

    final skill = _skills[skillId];
    if (skill == null) throw SkillNotFoundException(skillId);

    if (skill.isEnabled) return;

    debugPrint('[SkillManager] Enabling skill: $skillId');

    _skills[skillId] = skill.copyWith(isEnabled: true);
    await _persistEnabledSkills();
    _addLog(skillId, 'enable', true);

    notifyListeners();
  }

  /// Disable a skill: deactivate its actions and prompt templates.
  Future<void> disable(String skillId) async {
    _ensureInitialized();

    final skill = _skills[skillId];
    if (skill == null) throw SkillNotFoundException(skillId);

    if (!skill.isEnabled) return;

    debugPrint('[SkillManager] Disabling skill: $skillId');

    _skills[skillId] = skill.copyWith(isEnabled: false);
    await _persistEnabledSkills();
    _addLog(skillId, 'disable', true);

    notifyListeners();
  }

  /// Toggle a skill's enabled state.
  Future<void> toggle(String skillId) async {
    _ensureInitialized();

    final skill = _skills[skillId];
    if (skill == null) throw SkillNotFoundException(skillId);

    if (skill.isEnabled) {
      await disable(skillId);
    } else {
      await enable(skillId);
    }
  }

  /// Increment usage count for a skill.
  void recordUsage(String skillId) {
    final skill = _skills[skillId];
    if (skill != null) {
      _skills[skillId] = skill.copyWith(usageCount: skill.usageCount + 1);
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // MCP Server Management
  // ═══════════════════════════════════════════════════════════════════════

  /// Register MCP servers defined by a skill.
  Future<void> registerMcpServers(String skillId) async {
    _ensureInitialized();

    final skill = _skills[skillId];
    if (skill == null) return;

    debugPrint('[SkillManager] Registering MCP servers for skill: $skillId');

    for (final mcpId in skill.mcpServers) {
      // Check if already registered
      if (_mcpServers.containsKey(mcpId)) {
        // Add skill ID to the existing server's skill IDs
        final existing = _mcpServers[mcpId]!;
        if (!existing.skillIds.contains(skillId)) {
          _mcpServers[mcpId] = existing.copyWith(
            skillIds: [...existing.skillIds, skillId],
          );
        }
        continue;
      }

      // Try to load MCP server config from skill manifest or create a placeholder
      final mcpServer = McpServer(
        id: mcpId,
        name: mcpId,
        type: 'stdio',
        command: '',
        skillIds: [skillId],
        registeredAt: DateTime.now(),
      );

      _mcpServers[mcpId] = mcpServer;
    }

    await _persistMcpServers();
    notifyListeners();
  }

  /// Enable an MCP server.
  Future<void> enableMcpServer(String serverId) async {
    _ensureInitialized();

    final server = _mcpServers[serverId];
    if (server == null) throw McpServerException('Server not found', serverId: serverId);

    debugPrint('[SkillManager] Enabling MCP server: $serverId');

    _mcpServers[serverId] = server.copyWith(
      isEnabled: true,
      status: McpServerStatus.starting,
    );
    notifyListeners();

    // Simulate connection start
    await Future.delayed(const Duration(milliseconds: 500));

    _mcpServers[serverId] = _mcpServers[serverId]!.copyWith(
      status: McpServerStatus.running,
      lastConnectedAt: DateTime.now(),
    );

    await _persistMcpServers();
    notifyListeners();
  }

  /// Disable an MCP server.
  Future<void> disableMcpServer(String serverId) async {
    _ensureInitialized();

    final server = _mcpServers[serverId];
    if (server == null) return;

    debugPrint('[SkillManager] Disabling MCP server: $serverId');

    _mcpServers[serverId] = server.copyWith(
      isEnabled: false,
      status: McpServerStatus.stopped,
    );

    await _persistMcpServers();
    notifyListeners();
  }

  /// Toggle an MCP server's enabled state.
  Future<void> toggleMcpServer(String serverId) async {
    final server = _mcpServers[serverId];
    if (server == null) return;

    if (server.isEnabled) {
      await disableMcpServer(serverId);
    } else {
      await enableMcpServer(serverId);
    }
  }

  /// Get an MCP server by ID.
  McpServer? getMcpServer(String id) => _mcpServers[id];

  /// Get all MCP servers associated with a skill.
  List<McpServer> getMcpServersForSkill(String skillId) {
    return List.unmodifiable(
      _mcpServers.values.where((s) => s.skillIds.contains(skillId)),
    );
  }

  /// Remove a custom MCP server.
  Future<void> removeMcpServer(String serverId) async {
    _ensureInitialized();

    _mcpServers.remove(serverId);
    await _persistMcpServers();
    notifyListeners();
  }

  /// Add a custom MCP server (user-defined, not from a skill).
  Future<void> addCustomMcpServer(McpServer server) async {
    _ensureInitialized();

    _mcpServers[server.id] = server;
    await _persistMcpServers();
    notifyListeners();
  }

  /// Update an MCP server's configuration.
  Future<void> updateMcpServer(McpServer server) async {
    _ensureInitialized();

    if (!_mcpServers.containsKey(server.id)) {
      throw McpServerException('Server not found', serverId: server.id);
    }

    _mcpServers[server.id] = server;
    await _persistMcpServers();
    notifyListeners();
  }

  // ── Private: MCP unregistration ────────────────

  Future<void> _unregisterMcpServersForSkill(String skillId) async {
    final serversToCheck = _mcpServers.values.where((s) => s.skillIds.contains(skillId)).toList();

    for (final server in serversToCheck) {
      final newSkillIds = server.skillIds.where((id) => id != skillId).toList();

      if (newSkillIds.isEmpty) {
        // No other skills use this server - disable and remove
        if (server.isEnabled) {
          await disableMcpServer(server.id);
        }
        _mcpServers.remove(server.id);
      } else {
        // Other skills still use it - just update skill IDs
        _mcpServers[server.id] = server.copyWith(skillIds: newSkillIds);
      }
    }

    await _persistMcpServers();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Private: Built-in Skills
  // ═══════════════════════════════════════════════════════════════════════

  void _registerBuiltInSkills() {
    _builtInSkills.clear();

    // Built-in Flutter Development Skill
    _builtInSkills.add(Skill(
      id: 'flutter_dev',
      name: 'Flutter开发助手',
      version: '1.0.0',
      description: 'Flutter开发相关的Prompt模板和Actions，包括项目创建、Widget生成、状态管理模板等',
      author: 'mobilecode-team',
      tags: const ['flutter', 'dart', 'mobile', 'built-in'],
      actions: const [
        'flutter.create_project',
        'flutter.add_widget',
        'flutter.add_state_management',
        'flutter.run_app',
        'flutter.hot_reload',
      ],
      prompts: const [
        'flutter_code_gen',
        'flutter_widget_guide',
        'flutter_state_management',
        'flutter_best_practices',
      ],
      mcpServers: const [],
      source: SkillSource.builtIn,
      isEnabled: true,
      isInstalled: true,
      installedAt: DateTime.now(),
    ));

    // Built-in Git Skill
    _builtInSkills.add(Skill(
      id: 'git_helper',
      name: 'Git助手',
      version: '1.0.0',
      description: 'Git版本控制相关的Prompt模板和Actions，提交信息生成、分支管理、冲突解决等',
      author: 'mobilecode-team',
      tags: const ['git', 'version-control', 'built-in'],
      actions: const [
        'git.generate_commit_message',
        'git.suggest_branch_name',
        'git.resolve_conflict',
        'git.view_history',
      ],
      prompts: const [
        'git_commit_message_gen',
        'git_workflow_guide',
        'git_conflict_resolution',
      ],
      mcpServers: const [],
      source: SkillSource.builtIn,
      isEnabled: true,
      isInstalled: true,
      installedAt: DateTime.now(),
    ));

    // Built-in Code Review Skill
    _builtInSkills.add(Skill(
      id: 'code_review',
      name: '代码审查助手',
      version: '1.0.0',
      description: '代码审查相关的Prompt模板，帮助发现潜在问题、优化建议和最佳实践检查',
      author: 'mobilecode-team',
      tags: const ['code-review', 'quality', 'built-in'],
      actions: const [
        'ai.review_code',
        'ai.find_bugs',
        'ai.suggest_optimizations',
      ],
      prompts: const [
        'code_review_checklist',
        'bug_hunting_guide',
        'performance_audit',
      ],
      mcpServers: const [],
      source: SkillSource.builtIn,
      isEnabled: true,
      isInstalled: true,
      installedAt: DateTime.now(),
    ));

    // Built-in MCP-enabled skill (GitHub tools)
    _builtInSkills.add(Skill(
      id: 'github_tools',
      name: 'GitHub工具集',
      version: '1.0.0',
      description: '通过MCP协议连接GitHub API，支持Issue管理、PR审查、仓库操作等',
      author: 'mobilecode-team',
      tags: const ['github', 'mcp', 'integration', 'built-in'],
      actions: const [
        'github.list_issues',
        'github.create_pr',
        'github.review_pr',
      ],
      prompts: const [
        'github_issue_template',
        'github_pr_description',
      ],
      mcpServers: const ['github_mcp_server'],
      source: SkillSource.builtIn,
      isEnabled: false,
      isInstalled: true,
      installedAt: DateTime.now(),
    ));

    // Add built-in skills to main registry
    for (final skill in _builtInSkills) {
      _skills[skill.id] = skill;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Private: Persistence
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _persistSkills() async {
    try {
      final installed = _skills.values.where((s) => s.isInstalled && s.source != SkillSource.builtIn).toList();
      final jsonList = installed.map((s) => jsonEncode(s.toJson())).toList();
      await _prefs?.setStringList(_skillsKey, jsonList);
    } catch (e) {
      debugPrint('[SkillManager] Failed to persist skills: $e');
    }
  }

  Future<void> _loadPersistedSkills() async {
    try {
      final jsonList = _prefs?.getStringList(_skillsKey) ?? [];
      for (final jsonStr in jsonList) {
        try {
          final skill = Skill.fromJsonString(jsonStr);
          // Don't override built-in skills
          if (!_skills.containsKey(skill.id)) {
            _skills[skill.id] = skill;
          }
        } catch (e) {
          debugPrint('[SkillManager] Failed to parse skill: $e');
        }
      }
      debugPrint('[SkillManager] Loaded ${_skills.length} skills');
    } catch (e) {
      debugPrint('[SkillManager] Failed to load skills: $e');
    }
  }

  Future<void> _persistMcpServers() async {
    try {
      final jsonList = _mcpServers.values.map((s) => jsonEncode(s.toJson())).toList();
      await _prefs?.setStringList(_mcpServersKey, jsonList);
    } catch (e) {
      debugPrint('[SkillManager] Failed to persist MCP servers: $e');
    }
  }

  Future<void> _loadPersistedMcpServers() async {
    try {
      final jsonList = _prefs?.getStringList(_mcpServersKey) ?? [];
      for (final jsonStr in jsonList) {
        try {
          final server = McpServer.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
          // Reset runtime-only fields
          server.status = server.isEnabled ? McpServerStatus.stopped : McpServerStatus.stopped;
          _mcpServers[server.id] = server;
        } catch (e) {
          debugPrint('[SkillManager] Failed to parse MCP server: $e');
        }
      }
      debugPrint('[SkillManager] Loaded ${_mcpServers.length} MCP servers');
    } catch (e) {
      debugPrint('[SkillManager] Failed to load MCP servers: $e');
    }
  }

  Future<void> _persistEnabledSkills() async {
    try {
      final enabled = _skills.values.where((s) => s.isEnabled).map((s) => s.id).toList();
      await _prefs?.setStringList(_enabledSkillsKey, enabled);
    } catch (e) {
      debugPrint('[SkillManager] Failed to persist enabled skills: $e');
    }
  }

  Future<void> _loadPersistedLogs() async {
    try {
      final jsonList = _prefs?.getStringList(_logsKey) ?? [];
      _logs.addAll(
        jsonList.map((s) => SkillInstallLog.fromJson(jsonDecode(s) as Map<String, dynamic>)),
      );
    } catch (e) {
      debugPrint('[SkillManager] Failed to load logs: $e');
    }
  }

  void _addLog(String skillId, String operation, bool success, {String? error}) {
    final log = SkillInstallLog(
      skillId: skillId,
      operation: operation,
      timestamp: DateTime.now(),
      success: success,
      error: error,
    );
    _logs.add(log);

    // Persist last 100 logs
    if (_logs.length > 100) {
      _logs.removeAt(0);
    }

    try {
      final jsonList = _logs.map((l) => jsonEncode(l.toJson())).toList();
      _prefs?.setStringList(_logsKey, jsonList);
    } catch (e) {
      debugPrint('[SkillManager] Failed to persist log: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Private: Helpers
  // ═══════════════════════════════════════════════════════════════════════

  /// Try alternate YAML filenames.
  Future<String?> _tryFetchYamlAlternate(String owner, String repo) async {
    for (final filename in ['skill.yml', 'Skill.yaml', 'Skill.yml']) {
      for (final branch in ['main', 'master']) {
        final uri = Uri.https(
          'raw.githubusercontent.com',
          '/$owner/$repo/$branch/$filename',
        );
        final response = await http.get(uri);
        if (response.statusCode == 200) {
          return response.body;
        }
      }
    }
    return null;
  }

  /// Create a Skill from GitHub repo metadata when no skill.yaml is found.
  Skill _skillFromGitHubMetadata(String githubUrl, String owner, String repo) {
    return Skill(
      id: '${owner}_$repo',
      name: repo,
      version: '1.0.0',
      description: 'Imported from GitHub: $owner/$repo',
      author: owner,
      tags: const ['github', 'imported'],
      actions: const [],
      prompts: const [],
      mcpServers: const [],
      source: SkillSource.github,
      githubUrl: githubUrl,
    );
  }

  /// Parse a simplified YAML-like format (key: value pairs).
  ///
  /// This is a lightweight parser for simple skill.yaml files.
  /// For complex YAML, consider using the `yaml` package.
  Map<String, dynamic> _parseYamlLike(String content) {
    final result = <String, dynamic>{};
    String? currentListKey;
    final currentList = <String>[];

    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

      // Check if it's a list item
      if (trimmed.startsWith('- ')) {
        final value = trimmed.substring(2).trim();
        // Remove quotes if present
        currentList.add(value.replaceAll(RegExp(r"^['"""'"]|["'""'"]$"), ''));
        continue;
      }

      // If we were collecting a list, save it before moving on
      if (currentListKey != null && currentList.isNotEmpty) {
        result[currentListKey] = List.unmodifiable(currentList);
        currentList.clear();
        currentListKey = null;
      }

      // Parse key: value
      final colonIndex = trimmed.indexOf(':');
      if (colonIndex > 0) {
        final key = trimmed.substring(0, colonIndex).trim();
        final value = trimmed.substring(colonIndex + 1).trim();

        if (value.isEmpty) {
          // This key likely has a list below it
          currentListKey = key;
        } else {
          // Remove quotes
          final cleanValue = value.replaceAll(RegExp(r"^['"""'"]|["'""'"]$"), '');
          result[key] = cleanValue;
        }
      }
    }

    // Don't forget the last list
    if (currentListKey != null && currentList.isNotEmpty) {
      result[currentListKey] = List.unmodifiable(currentList);
    }

    return result;
  }

  /// Compare two semantic versions.
  bool _isNewerVersion(String newVersion, String currentVersion) {
    try {
      final newParts = newVersion.split('.').map(int.parse).toList();
      final currentParts = currentVersion.split('.').map(int.parse).toList();

      for (var i = 0; i < 3; i++) {
        final newPart = i < newParts.length ? newParts[i] : 0;
        final currentPart = i < currentParts.length ? currentParts[i] : 0;
        if (newPart > currentPart) return true;
        if (newPart < currentPart) return false;
      }
      return false; // equal
    } catch (e) {
      // Non-semver: just compare strings
      return newVersion != currentVersion;
    }
  }

  /// Demo data for when GitHub API is unavailable.
  List<Skill> _getDemoGitHubSkills() {
    return [
      Skill(
        id: 'flutter_state_management',
        name: 'Flutter状态管理',
        version: '1.2.0',
        description: 'Provider、Riverpod、Bloc、GetX等状态管理方案的Prompt模板和代码生成',
        author: 'flutter-community',
        tags: const ['flutter', 'state-management', 'riverpod', 'bloc'],
        actions: const [
          'flutter.add_riverpod_provider',
          'flutter.add_bloc_pattern',
          'flutter.generate_state_class',
        ],
        prompts: const [
          'riverpod_setup_guide',
          'bloc_pattern_template',
          'state_management_comparison',
        ],
        mcpServers: const [],
        source: SkillSource.github,
        githubUrl: 'https://github.com/flutter-community/mobilecode-skill-state-management',
        rating: 4.5,
        installCount: 2340,
      ),
      Skill(
        id: 'api_integration',
        name: 'API集成助手',
        version: '1.0.3',
        description: 'REST API和GraphQL集成相关的代码生成、错误处理、缓存策略模板',
        author: 'mobilecode-team',
        tags: const ['api', 'http', 'graphql', 'dio'],
        actions: const [
          'flutter.create_api_service',
          'flutter.add_error_handler',
          'flutter.setup_dio',
        ],
        prompts: const [
          'api_integration_template',
          'graphql_query_builder',
          'error_handling_pattern',
        ],
        mcpServers: const [],
        source: SkillSource.github,
        githubUrl: 'https://github.com/mobilecode-team/mobilecode-skill-api',
        rating: 4.2,
        installCount: 1890,
      ),
      Skill(
        id: 'ui_component_library',
        name: 'UI组件库生成器',
        version: '2.0.0',
        description: '快速生成Flutter UI组件、表单、对话框、列表等常用界面元素',
        author: 'ui-wizard',
        tags: const ['flutter', 'ui', 'components', 'design'],
        actions: const [
          'flutter.create_custom_widget',
          'flutter.generate_form',
          'flutter.create_dialog',
        ],
        prompts: const [
          'custom_widget_template',
          'responsive_layout_guide',
          'animation_pattern',
        ],
        mcpServers: const [],
        source: SkillSource.github,
        githubUrl: 'https://github.com/ui-wizard/mobilecode-skill-ui',
        rating: 4.8,
        installCount: 5670,
      ),
    ];
  }
}
