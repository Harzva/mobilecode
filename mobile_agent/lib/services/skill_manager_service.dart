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

class RegistrySourceException implements Exception {
  final String message;
  RegistrySourceException(this.message);
  @override
  String toString() => 'RegistrySourceException: $message';
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
  static const String _builtInSkillStateKey = 'skill_manager_builtin_skill_state';

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

    // Apply persisted built-in uninstall/enable overrides after defaults register.
    await _loadPersistedBuiltInSkillState();

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

  /// Build a compact prompt context from enabled HTML/UI skills.
  ///
  /// This is the bridge from Skill Manager state into the mini-agent loop. It
  /// intentionally returns guidance, not executable plugin code.
  Future<String> buildHtmlGenerationSkillContext() async {
    if (!_initialized) {
      await initialize();
    }

    final active = _skills.values
        .where((skill) => skill.isInstalled && skill.isEnabled)
        .where((skill) =>
            skill.tags.any((tag) {
              final lower = tag.toLowerCase();
              return lower == 'html' ||
                  lower == 'ui' ||
                  lower == 'ux' ||
                  lower == 'accessibility' ||
                  lower == 'animation' ||
                  lower == 'design-system';
            }) ||
            skill.actions.any((action) => action.startsWith('html.') || action.startsWith('a11y.') || action.startsWith('motion.')))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    if (active.isEmpty) {
      return 'No optional HTML/UI skills are enabled. Use the baseline mobile-first HTML requirements only.';
    }

    final buffer = StringBuffer()
      ..writeln('Active MobileCode HTML/UI skills:')
      ..writeln('- Apply these as product-native guidance, not as external tool execution.');

    for (final skill in active.take(8)) {
      buffer.writeln('- ${skill.id}: ${skill.description}');
      if (skill.actions.isNotEmpty) {
        buffer.writeln('  Actions: ${skill.actions.take(3).join(', ')}');
      }
      if (skill.prompts.isNotEmpty) {
        buffer.writeln('  Prompt gates: ${skill.prompts.take(3).join(', ')}');
      }
    }

    buffer.writeln('Required HTML output gates: mobile-first layout, semantic HTML, touch-friendly controls, accessible labels/focus states, reduced-motion fallback, cohesive visual system, no remote assets unless explicitly requested.');
    return buffer.toString().trim();
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

  /// Search SkillHub as a discovery source, then normalize results to GitHub-backed skills.
  ///
  /// MobileCode never runs install commands from SkillHub directly. A result is usable
  /// only when it can resolve to a GitHub provenance URL that can be previewed through
  /// [importFromGitHub] before installation.
  Future<List<Skill>> searchSkillHubSkills({String? query, int limit = 12}) async {
    if (!_initialized) {
      await initialize();
    }
    final searchQuery = (query == null || query.trim().isEmpty) ? 'html ui design mobile' : query.trim();

    try {
      final uri = Uri.https('www.skillhub.club', '/api/v1/skills/search');
      final response = await http.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'query': searchQuery,
          'limit': limit,
          'method': 'hybrid',
        }),
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        throw RegistrySourceException('SkillHub search returned HTTP ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);
      final items = _extractRegistryItems(decoded);
      final results = <Skill>[];
      for (final item in items) {
        final skill = _skillFromSkillHubItem(item);
        if (skill != null) results.add(skill);
      }
      if (results.isNotEmpty) return List.unmodifiable(results.take(limit));
    } catch (e) {
      debugPrint('[SkillManager] SkillHub search fallback: $e');
    }

    return _getCuratedSkillHubSkills(searchQuery, limit: limit);
  }

  /// Search MCPHub-compatible sources and return disabled MCP server candidates.
  ///
  /// MCPHub gateway/registry entries are treated as metadata only. The returned
  /// servers are not started or enabled until the user reviews and registers them.
  Future<List<McpServer>> searchMcpHubServers({String? query, int limit = 12}) async {
    if (!_initialized) {
      await initialize();
    }
    final searchQuery = (query == null || query.trim().isEmpty) ? 'github fetch browser filesystem' : query.trim();

    try {
      final uri = Uri.https(
        'api.github.com',
        '/search/repositories',
        {
          'q': 'mcp server $searchQuery in:name,description,topics',
          'sort': 'stars',
          'order': 'desc',
          'per_page': '$limit',
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw RegistrySourceException('MCP registry search returned HTTP ${response.statusCode}');
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final items = decoded['items'] as List<dynamic>? ?? const [];
      final results = <McpServer>[];
      for (final item in items) {
        if (item is! Map<String, dynamic>) continue;
        final server = _mcpServerFromGitHubRepo(item);
        if (server != null) results.add(server);
      }
      if (results.isNotEmpty) return List.unmodifiable(results.take(limit));
    } catch (e) {
      debugPrint('[SkillManager] MCPHub search fallback: $e');
    }

    return _getCuratedMcpHubServers(searchQuery, limit: limit);
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

    _registerBuiltInHtmlDesignSkills();

    // Add built-in skills to main registry
    for (final skill in _builtInSkills) {
      _skills[skill.id] = skill;
    }
  }

  void _registerBuiltInHtmlDesignSkills() {
    final now = DateTime.now();
    final skills = [
      Skill(
        id: 'frontend_design',
        name: 'Frontend Design',
        version: '1.0.0',
        description: 'HTML-first visual direction, typography, color, layout, motion, and non-generic product UI guidance internalized for MobileCode artifacts.',
        author: 'mobilecode-team',
        tags: const ['html', 'frontend', 'design', 'built-in', 'default'],
        actions: const [
          'html.choose_visual_direction',
          'html.compose_responsive_layout',
          'html.refine_visual_system',
        ],
        prompts: const [
          'frontend_design_brief',
          'html_visual_quality_checklist',
          'mobile_preview_polish',
        ],
        mcpServers: const [],
        source: SkillSource.builtIn,
        githubUrl: 'https://github.com/anthropics/skills',
        isEnabled: true,
        isInstalled: true,
        installedAt: now,
      ),
      Skill(
        id: 'ui_ux_pro_max',
        name: 'UI UX Pro Max',
        version: '1.0.0',
        description: 'Product-grade UX flow, information hierarchy, interaction states, and mobile-first polish for generated HTML experiences.',
        author: 'mobilecode-team',
        tags: const ['ux', 'mobile-ui', 'html', 'built-in', 'default'],
        actions: const [
          'ux.map_user_flow',
          'ux.design_empty_loading_error_states',
          'ux.audit_touch_targets',
        ],
        prompts: const [
          'mobile_ux_flow_review',
          'ui_state_completeness',
          'tap_target_accessibility',
        ],
        mcpServers: const [],
        source: SkillSource.builtIn,
        githubUrl: 'https://github.com/nextlevelbuilder/ui-ux-pro-max-skill',
        isEnabled: true,
        isInstalled: true,
        installedAt: now,
      ),
      Skill(
        id: 'shadcn_ui',
        name: 'shadcn/ui Pattern Kit',
        version: '1.0.0',
        description: 'Ownership-oriented component patterns, variants, dialogs, forms, cards, and registry thinking adapted to plain HTML/CSS and future React exports.',
        author: 'mobilecode-team',
        tags: const ['components', 'shadcn', 'html', 'built-in', 'default'],
        actions: const [
          'ui.compose_component_variants',
          'ui.design_dialog_form_controls',
          'ui.normalize_component_tokens',
        ],
        prompts: const [
          'component_variant_matrix',
          'html_component_contract',
          'registry_component_review',
        ],
        mcpServers: const [],
        source: SkillSource.builtIn,
        githubUrl: 'https://github.com/giuseppe-trisciuoglio/developer-kit',
        isEnabled: true,
        isInstalled: true,
        installedAt: now,
      ),
      Skill(
        id: 'stitch_html_design',
        name: 'Stitch HTML Design',
        version: '1.0.0',
        description: 'Prompt-to-interface structure, screenshot-inspired design translation, and high-fidelity HTML screen generation for MobileCode previews.',
        author: 'mobilecode-team',
        tags: const ['stitch', 'html', 'design-system', 'built-in', 'default'],
        actions: const [
          'html.translate_design_prompt',
          'html.extract_design_tokens',
          'html.generate_preview_screen',
        ],
        prompts: const [
          'stitch_style_html_prompt',
          'design_token_extraction',
          'mobile_webview_screen_spec',
        ],
        mcpServers: const [],
        source: SkillSource.builtIn,
        githubUrl: 'https://github.com/google-labs-code/stitch-skills',
        isEnabled: true,
        isInstalled: true,
        installedAt: now,
      ),
      Skill(
        id: 'web_accessibility',
        name: 'Web Accessibility',
        version: '1.0.0',
        description: 'Accessibility defaults for generated HTML: semantic structure, focus order, contrast, motion reduction, labels, and keyboard affordances.',
        author: 'mobilecode-team',
        tags: const ['accessibility', 'wcag', 'html', 'built-in', 'default'],
        actions: const [
          'a11y.audit_semantics',
          'a11y.check_focus_order',
          'a11y.enforce_motion_preferences',
        ],
        prompts: const [
          'html_accessibility_checklist',
          'semantic_markup_review',
          'keyboard_navigation_review',
        ],
        mcpServers: const [],
        source: SkillSource.builtIn,
        githubUrl: 'https://github.com/supercent-io/skills-template',
        isEnabled: true,
        isInstalled: true,
        installedAt: now,
      ),
      Skill(
        id: 'web_design_guidelines',
        name: 'Web Design Guidelines',
        version: '1.0.0',
        description: 'Vercel-style web craft guidance for responsive composition, performance-aware UI, hierarchy, and deployable web artifact quality.',
        author: 'mobilecode-team',
        tags: const ['web', 'guidelines', 'performance', 'built-in', 'default'],
        actions: const [
          'web.audit_visual_hierarchy',
          'web.check_responsive_breakpoints',
          'web.review_deployable_quality',
        ],
        prompts: const [
          'web_design_review',
          'responsive_artifact_gate',
          'deployable_html_quality',
        ],
        mcpServers: const [],
        source: SkillSource.builtIn,
        githubUrl: 'https://github.com/vercel-labs/agent-skills',
        isEnabled: true,
        isInstalled: true,
        installedAt: now,
      ),
      Skill(
        id: 'ui_animation',
        name: 'UI Animation',
        version: '1.0.0',
        description: 'CSS-first motion patterns, micro-interactions, page reveal timing, and reduced-motion fallbacks for HTML previews.',
        author: 'mobilecode-team',
        tags: const ['animation', 'css', 'motion', 'built-in', 'default'],
        actions: const [
          'motion.plan_page_reveal',
          'motion.add_micro_interactions',
          'motion.add_reduced_motion_fallback',
        ],
        prompts: const [
          'css_motion_direction',
          'micro_interaction_review',
          'reduced_motion_gate',
        ],
        mcpServers: const [],
        source: SkillSource.builtIn,
        githubUrl: 'https://github.com/mblode/agent-skills',
        isEnabled: true,
        isInstalled: true,
        installedAt: now,
      ),
      Skill(
        id: 'figma_implement_design',
        name: 'Figma Implement Design',
        version: '1.0.0',
        description: 'Figma-to-code discipline internalized as design context, asset fidelity, token translation, visual parity, and responsive validation.',
        author: 'mobilecode-team',
        tags: const ['figma', 'design-implementation', 'html', 'built-in', 'default'],
        actions: const [
          'figma.extract_design_context',
          'figma.translate_tokens_to_html',
          'figma.validate_visual_parity',
        ],
        prompts: const [
          'figma_to_html_plan',
          'design_asset_fidelity',
          'visual_parity_checklist',
        ],
        mcpServers: const [],
        source: SkillSource.builtIn,
        githubUrl: 'https://github.com/figma/mcp-server-guide',
        isEnabled: true,
        isInstalled: true,
        installedAt: now,
      ),
      Skill(
        id: 'tailwind_design_system',
        name: 'Tailwind Design System',
        version: '1.0.0',
        description: 'Tokenized spacing, typography, color, utility naming, and reusable design-system rules adapted for generated HTML/CSS.',
        author: 'mobilecode-team',
        tags: const ['tailwind', 'design-system', 'tokens', 'built-in', 'default'],
        actions: const [
          'design_system.define_tokens',
          'design_system.normalize_spacing',
          'design_system.audit_consistency',
        ],
        prompts: const [
          'tailwind_token_plan',
          'html_css_tokenization',
          'design_system_consistency_review',
        ],
        mcpServers: const [],
        source: SkillSource.builtIn,
        githubUrl: 'https://github.com/wshobson/agents',
        isEnabled: true,
        isInstalled: true,
        installedAt: now,
      ),
    ];

    _builtInSkills.addAll(skills);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Private: Persistence
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _persistSkills() async {
    try {
      final installed = _skills.values.where((s) => s.isInstalled && s.source != SkillSource.builtIn).toList();
      final jsonList = installed.map((s) => jsonEncode(s.toJson())).toList();
      await _prefs?.setStringList(_skillsKey, jsonList);
      await _persistBuiltInSkillState();
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
      await _persistBuiltInSkillState();
    } catch (e) {
      debugPrint('[SkillManager] Failed to persist enabled skills: $e');
    }
  }

  Future<void> _persistBuiltInSkillState() async {
    final builtInState = <String, dynamic>{};
    for (final skill in _skills.values.where((s) => s.source == SkillSource.builtIn)) {
      builtInState[skill.id] = {
        'isInstalled': skill.isInstalled,
        'isEnabled': skill.isEnabled,
      };
    }
    await _prefs?.setString(_builtInSkillStateKey, jsonEncode(builtInState));
  }

  Future<void> _loadPersistedBuiltInSkillState() async {
    try {
      final raw = _prefs?.getString(_builtInSkillStateKey);
      if (raw == null || raw.isEmpty) return;

      final state = jsonDecode(raw) as Map<String, dynamic>;
      for (final entry in state.entries) {
        final skill = _skills[entry.key];
        final value = entry.value;
        if (skill == null || skill.source != SkillSource.builtIn || value is! Map<String, dynamic>) {
          continue;
        }
        _skills[entry.key] = skill.copyWith(
          isInstalled: value['isInstalled'] as bool? ?? skill.isInstalled,
          isEnabled: value['isEnabled'] as bool? ?? skill.isEnabled,
        );
      }
    } catch (e) {
      debugPrint('[SkillManager] Failed to load built-in skill state: $e');
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
        currentList.add(_stripYamlQuotes(value));
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
          result[key] = _stripYamlQuotes(value);
        }
      }
    }

    // Don't forget the last list
    if (currentListKey != null && currentList.isNotEmpty) {
      result[currentListKey] = List.unmodifiable(currentList);
    }

    return result;
  }

  String _stripYamlQuotes(String value) {
    final trimmed = value.trim();
    if (trimmed.length < 2) return trimmed;

    final first = trimmed[0];
    final last = trimmed[trimmed.length - 1];
    if ((first == "'" && last == "'") || (first == '"' && last == '"')) {
      return trimmed.substring(1, trimmed.length - 1);
    }
    return trimmed;
  }

  List<Map<String, dynamic>> _extractRegistryItems(dynamic decoded) {
    if (decoded is List) {
      return decoded.whereType<Map<String, dynamic>>().toList();
    }
    if (decoded is! Map<String, dynamic>) return const [];
    for (final key in ['results', 'skills', 'items', 'data']) {
      final value = decoded[key];
      if (value is List) return value.whereType<Map<String, dynamic>>().toList();
      if (value is Map<String, dynamic>) {
        final nested = _extractRegistryItems(value);
        if (nested.isNotEmpty) return nested;
      }
    }
    return const [];
  }

  Skill? _skillFromSkillHubItem(Map<String, dynamic> item) {
    final githubUrl = _extractGitHubUrl(item);
    if (githubUrl == null) return null;

    final name = _stringField(item, const ['name', 'title', 'skillName']) ?? _repoNameFromGitHubUrl(githubUrl);
    final author = _stringField(item, const ['author', 'owner', 'publisher']) ?? _repoOwnerFromGitHubUrl(githubUrl);
    final description = _stringField(item, const ['description', 'summary', 'readme']) ??
        'Imported from SkillHub discovery source: $githubUrl';
    final id = 'skillhub_${_repoSlugFromGitHubUrl(githubUrl)}';

    return Skill(
      id: id,
      name: name,
      version: _stringField(item, const ['version']) ?? '1.0.0',
      description: description,
      author: author,
      tags: const ['skillhub', 'github', 'external-registry'],
      actions: const [],
      prompts: const [],
      mcpServers: const [],
      source: SkillSource.github,
      githubUrl: githubUrl,
      installCount: _intField(item, const ['downloads', 'installCount', 'stars']) ?? 0,
    );
  }

  McpServer? _mcpServerFromGitHubRepo(Map<String, dynamic> repo) {
    final url = repo['html_url'] as String?;
    final fullName = repo['full_name'] as String?;
    if (url == null || fullName == null) return null;
    final name = repo['name'] as String? ?? fullName.split('/').last;
    final description = repo['description'] as String?;
    final packageName = _guessNpmPackageName(fullName, name);
    return McpServer(
      id: 'mcphub_${fullName.replaceAll(RegExp(r'[^A-Za-z0-9_]+'), '_')}',
      name: name,
      type: 'stdio',
      command: packageName == null ? '' : 'npx -y $packageName',
      description: description == null ? 'MCP server discovered from MCPHub-compatible GitHub provenance: $url' : '$description\n\nSource: $url',
      version: 'registry-preview',
      isEnabled: false,
      status: McpServerStatus.stopped,
      logs: const [
        'Imported as disabled metadata. Review command, environment variables, and permissions before enabling.',
      ],
    );
  }

  List<Skill> _getCuratedSkillHubSkills(String query, {int limit = 12}) {
    final curated = [
      _curatedSkill(
        id: 'skillhub_frontend_design',
        name: 'Frontend Design',
        description: 'HTML/UI design direction, typography, layout, visual quality, and mobile preview polish.',
        githubUrl: 'https://github.com/anthropics/skills',
      ),
      _curatedSkill(
        id: 'skillhub_ui_ux_pro_max',
        name: 'UI UX Pro Max',
        description: 'Mobile UX flow, interface state coverage, and product-grade UI hierarchy.',
        githubUrl: 'https://github.com/nextlevelbuilder/ui-ux-pro-max-skill',
      ),
      _curatedSkill(
        id: 'skillhub_shadcn_ui',
        name: 'shadcn/ui Pattern Kit',
        description: 'Owned component patterns, variants, dialogs, forms, and registry-style component thinking.',
        githubUrl: 'https://github.com/giuseppe-trisciuoglio/developer-kit',
      ),
      _curatedSkill(
        id: 'skillhub_stitch_html_design',
        name: 'Stitch HTML Design',
        description: 'Prompt-to-interface structure and high-fidelity HTML screen generation.',
        githubUrl: 'https://github.com/google-labs-code/stitch-skills',
      ),
      _curatedSkill(
        id: 'skillhub_web_accessibility',
        name: 'Web Accessibility',
        description: 'Semantic HTML, focus order, contrast, labels, and reduced-motion defaults.',
        githubUrl: 'https://github.com/supercent-io/skills-template',
      ),
      _curatedSkill(
        id: 'skillhub_web_design_guidelines',
        name: 'Web Design Guidelines',
        description: 'Responsive composition, deployable HTML quality, and performance-aware web UI.',
        githubUrl: 'https://github.com/vercel-labs/agent-skills',
      ),
      _curatedSkill(
        id: 'skillhub_ui_animation',
        name: 'UI Animation',
        description: 'CSS-first motion, micro-interactions, page reveals, and reduced-motion fallback.',
        githubUrl: 'https://github.com/mblode/agent-skills',
      ),
      _curatedSkill(
        id: 'skillhub_figma_implement_design',
        name: 'Figma Implement Design',
        description: 'Design context extraction, token translation, asset fidelity, and visual parity discipline.',
        githubUrl: 'https://github.com/figma/mcp-server-guide',
      ),
      _curatedSkill(
        id: 'skillhub_tailwind_design_system',
        name: 'Tailwind Design System',
        description: 'Tokenized spacing, typography, color, and reusable design-system rules.',
        githubUrl: 'https://github.com/wshobson/agents',
      ),
    ];

    final lower = query.toLowerCase();
    final filtered = curated
        .where((skill) =>
            lower.trim().isEmpty ||
            skill.name.toLowerCase().contains(lower) ||
            skill.description.toLowerCase().contains(lower) ||
            skill.tags.any((tag) => tag.toLowerCase().contains(lower)))
        .toList();
    return List.unmodifiable((filtered.isEmpty ? curated : filtered).take(limit));
  }

  Skill _curatedSkill({
    required String id,
    required String name,
    required String description,
    required String githubUrl,
  }) {
    return Skill(
      id: id,
      name: name,
      version: '1.0.0',
      description: description,
      author: _repoOwnerFromGitHubUrl(githubUrl),
      tags: const ['skillhub', 'github', 'html', 'ui', 'external-registry'],
      actions: const [],
      prompts: const [],
      mcpServers: const [],
      source: SkillSource.github,
      githubUrl: githubUrl,
    );
  }

  List<McpServer> _getCuratedMcpHubServers(String query, {int limit = 12}) {
    final servers = [
      McpServer(
        id: 'mcphub_github',
        name: 'GitHub MCP Server',
        type: 'stdio',
        command: 'npx -y @modelcontextprotocol/server-github',
        description: 'Repository, issue, and pull request tools. Requires a reviewed GitHub token in env.',
        version: 'registry-preview',
        env: const {'GITHUB_TOKEN': '<required>'},
      ),
      McpServer(
        id: 'mcphub_fetch',
        name: 'Fetch MCP Server',
        type: 'stdio',
        command: 'npx -y @modelcontextprotocol/server-fetch',
        description: 'HTTP fetch tools for documentation and public web content. Review network access before enabling.',
        version: 'registry-preview',
      ),
      McpServer(
        id: 'mcphub_filesystem',
        name: 'Filesystem MCP Server',
        type: 'stdio',
        command: 'npx -y @modelcontextprotocol/server-filesystem <workspace>',
        description: 'Workspace-bounded file access. Must be restricted to the MobileCode project directory.',
        version: 'registry-preview',
      ),
      McpServer(
        id: 'mcphub_playwright',
        name: 'Browser/Playwright MCP Server',
        type: 'stdio',
        command: 'npx -y @playwright/mcp',
        description: 'Browser automation for local preview QA. Keep disabled until the user confirms browser automation.',
        version: 'registry-preview',
      ),
    ];
    final lower = query.toLowerCase();
    final filtered = servers
        .where((server) =>
            lower.trim().isEmpty ||
            server.name.toLowerCase().contains(lower) ||
            (server.description ?? '').toLowerCase().contains(lower) ||
            server.command.toLowerCase().contains(lower))
        .toList();
    return List.unmodifiable((filtered.isEmpty ? servers : filtered).take(limit));
  }

  String? _extractGitHubUrl(Map<String, dynamic> item) {
    for (final key in ['githubUrl', 'github_url', 'repository', 'repo', 'url', 'sourceUrl', 'homepage']) {
      final value = item[key];
      if (value is String && value.contains('github.com/')) {
        return _normalizeGitHubUrl(value);
      }
      if (value is Map<String, dynamic>) {
        final nested = _extractGitHubUrl(value);
        if (nested != null) return nested;
      }
    }
    final encoded = jsonEncode(item);
    final match = RegExp(r'https?://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+').firstMatch(encoded);
    return match == null ? null : _normalizeGitHubUrl(match.group(0)!);
  }

  String? _stringField(Map<String, dynamic> item, List<String> keys) {
    for (final key in keys) {
      final value = item[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  int? _intField(Map<String, dynamic> item, List<String> keys) {
    for (final key in keys) {
      final value = item[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value);
    }
    return null;
  }

  String _normalizeGitHubUrl(String value) {
    final uri = Uri.tryParse(value.startsWith('http') ? value : 'https://$value');
    if (uri == null || !uri.host.contains('github.com') || uri.pathSegments.length < 2) {
      return value;
    }
    return 'https://github.com/${uri.pathSegments[0]}/${uri.pathSegments[1].replaceAll('.git', '')}';
  }

  String _repoOwnerFromGitHubUrl(String githubUrl) {
    final uri = Uri.tryParse(githubUrl);
    if (uri == null || uri.pathSegments.isEmpty) return 'unknown';
    return uri.pathSegments[0];
  }

  String _repoNameFromGitHubUrl(String githubUrl) {
    final uri = Uri.tryParse(githubUrl);
    if (uri == null || uri.pathSegments.length < 2) return githubUrl;
    return uri.pathSegments[1].replaceAll('.git', '');
  }

  String _repoSlugFromGitHubUrl(String githubUrl) {
    final uri = Uri.tryParse(githubUrl);
    if (uri == null || uri.pathSegments.length < 2) {
      return githubUrl.replaceAll(RegExp(r'[^A-Za-z0-9_]+'), '_');
    }
    return '${uri.pathSegments[0]}_${uri.pathSegments[1].replaceAll('.git', '')}'
        .replaceAll(RegExp(r'[^A-Za-z0-9_]+'), '_');
  }

  String? _guessNpmPackageName(String fullName, String name) {
    final lower = name.toLowerCase();
    if (!lower.contains('mcp')) return null;
    if (lower.startsWith('@')) return name;
    if (lower.startsWith('server-') || lower.startsWith('mcp-server-')) {
      return name;
    }
    return null;
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
