// lib/models/skill_model.dart
// Skill Model - Data models for Skill and MCP Server
// 技能数据模型

import 'dart:convert';

// ═══════════════════════════════════════════════════════════════════════════
// Enums
// ═══════════════════════════════════════════════════════════════════════════

/// Source type for a Skill.
/// 技能来源类型
enum SkillSource {
  /// 内置技能 - Built-in skill bundled with the app
  builtIn,

  /// GitHub一键导入 - Imported from GitHub repository
  github,

  /// 本地导入 - Imported from local ZIP file
  local,

  /// 用户自定义 - User-created skill
  userCreated,
}

/// Extension for SkillSource display and serialization.
extension SkillSourceExt on SkillSource {
  /// Display name in Chinese.
  String get displayName {
    switch (this) {
      case SkillSource.builtIn:
        return '内置';
      case SkillSource.github:
        return 'GitHub';
      case SkillSource.local:
        return '本地';
      case SkillSource.userCreated:
        return '自定义';
    }
  }

  /// Icon identifier for the source.
  String get iconName {
    switch (this) {
      case SkillSource.builtIn:
        return 'package';
      case SkillSource.github:
        return 'code';
      case SkillSource.local:
        return 'folder';
      case SkillSource.userCreated:
        return 'person';
    }
  }

  /// Serialize to string.
  String toJson() => name;

  /// Deserialize from string.
  static SkillSource fromString(String value) {
    return SkillSource.values.firstWhere(
      (e) => e.name == value,
      orElse: () => SkillSource.local,
    );
  }
}

/// Status of an MCP server connection.
/// MCP服务器连接状态
enum McpServerStatus {
  /// 已停止 - Server is not running
  stopped,

  /// 启动中 - Server is starting up
  starting,

  /// 运行中 - Server is running and connected
  running,

  /// 错误 - Server encountered an error
  error,
}

/// Extension for McpServerStatus display.
extension McpServerStatusExt on McpServerStatus {
  /// Display name in Chinese.
  String get displayName {
    switch (this) {
      case McpServerStatus.stopped:
        return '已停止';
      case McpServerStatus.starting:
        return '启动中';
      case McpServerStatus.running:
        return '运行中';
      case McpServerStatus.error:
        return '错误';
    }
  }

  /// Color associated with the status.
  /// (Uses hex values to avoid Flutter material dependency in model.)
  int get colorHex {
    switch (this) {
      case McpServerStatus.stopped:
        return 0xFF6B7280; // gray
      case McpServerStatus.starting:
        return 0xFFF59E0B; // amber
      case McpServerStatus.running:
        return 0xFF10B981; // green
      case McpServerStatus.error:
        return 0xFFEF4444; // red
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Skill Model
// ═══════════════════════════════════════════════════════════════════════════

/// A Skill is a reusable capability package for MobileCode Agent.
///
/// Structure:
/// ├── skill.yaml (metadata)
/// │   ├── id: "flutter_dev"
/// │   ├── name: "Flutter开发助手"
/// │   ├── version: "1.0.0"
/// │   ├── description: "Flutter开发相关的Prompt模板和Actions"
/// │   ├── author: "mobilecode-team"
/// │   ├── tags: ["flutter", "dart", "mobile"]
/// │   ├── icon: "flutter_logo.png"
/// │   ├── actions: ["flutter.create_project", "flutter.add_widget"]
/// │   ├── prompts: ["flutter_code_gen", "flutter_widget_guide"]
/// │   └── mcp_servers: ["flutter_analyzer"]
///
/// Source types:
/// - built_in: 内置技能
/// - github: GitHub一键导入
/// - local: 本地导入
/// - user_created: 用户自定义
class Skill {
  /// Unique identifier (e.g., "flutter_dev")
  final String id;

  /// Display name (e.g., "Flutter开发助手")
  final String name;

  /// Semantic version (e.g., "1.0.0")
  final String version;

  /// Short description of what this skill does
  final String description;

  /// Author or organization
  final String author;

  /// URL to icon image (optional)
  final String? iconUrl;

  /// Tags for categorization and search
  final List<String> tags;

  /// Registered action IDs this skill provides
  final List<String> actions;

  /// Prompt template IDs this skill provides
  final List<String> prompts;

  /// MCP server IDs this skill depends on
  final List<String> mcpServers;

  /// Where this skill came from
  final SkillSource source;

  /// Original GitHub URL (for github-sourced skills)
  final String? githubUrl;

  /// Local file path (for locally-sourced skills)
  final String? localPath;

  /// Whether the skill is currently enabled (runtime only)
  bool isEnabled;

  /// Whether the skill is installed
  bool isInstalled;

  /// When the skill was installed
  final DateTime? installedAt;

  /// How many times this skill has been used
  int usageCount;

  /// Optional README content (fetched from GitHub)
  final String? readme;

  /// Rating from users (0-5)
  final double rating;

  /// Number of downloads/installs
  final int installCount;

  Skill({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.author,
    this.iconUrl,
    required this.tags,
    required this.actions,
    required this.prompts,
    required this.mcpServers,
    required this.source,
    this.githubUrl,
    this.localPath,
    this.isEnabled = false,
    this.isInstalled = false,
    this.installedAt,
    this.usageCount = 0,
    this.readme,
    this.rating = 0.0,
    this.installCount = 0,
  });

  // ── Copy ─────────────────────────────────────────

  Skill copyWith({
    String? id,
    String? name,
    String? version,
    String? description,
    String? author,
    String? iconUrl,
    List<String>? tags,
    List<String>? actions,
    List<String>? prompts,
    List<String>? mcpServers,
    SkillSource? source,
    String? githubUrl,
    String? localPath,
    bool? isEnabled,
    bool? isInstalled,
    DateTime? installedAt,
    int? usageCount,
    String? readme,
    double? rating,
    int? installCount,
  }) {
    return Skill(
      id: id ?? this.id,
      name: name ?? this.name,
      version: version ?? this.version,
      description: description ?? this.description,
      author: author ?? this.author,
      iconUrl: iconUrl ?? this.iconUrl,
      tags: tags ?? List.unmodifiable(this.tags),
      actions: actions ?? List.unmodifiable(this.actions),
      prompts: prompts ?? List.unmodifiable(this.prompts),
      mcpServers: mcpServers ?? List.unmodifiable(this.mcpServers),
      source: source ?? this.source,
      githubUrl: githubUrl ?? this.githubUrl,
      localPath: localPath ?? this.localPath,
      isEnabled: isEnabled ?? this.isEnabled,
      isInstalled: isInstalled ?? this.isInstalled,
      installedAt: installedAt ?? this.installedAt,
      usageCount: usageCount ?? this.usageCount,
      readme: readme ?? this.readme,
      rating: rating ?? this.rating,
      installCount: installCount ?? this.installCount,
    );
  }

  // ── JSON Serialization ─────────────────────────

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'version': version,
      'description': description,
      'author': author,
      'iconUrl': iconUrl,
      'tags': tags,
      'actions': actions,
      'prompts': prompts,
      'mcpServers': mcpServers,
      'source': source.toJson(),
      'githubUrl': githubUrl,
      'localPath': localPath,
      'isEnabled': isEnabled,
      'isInstalled': isInstalled,
      'installedAt': installedAt?.toIso8601String(),
      'usageCount': usageCount,
      'readme': readme,
      'rating': rating,
      'installCount': installCount,
    };
  }

  factory Skill.fromJson(Map<String, dynamic> json) {
    return Skill(
      id: json['id'] as String,
      name: json['name'] as String,
      version: json['version'] as String,
      description: json['description'] as String,
      author: json['author'] as String,
      iconUrl: json['iconUrl'] as String?,
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? const [],
      actions: (json['actions'] as List<dynamic>?)?.cast<String>() ?? const [],
      prompts: (json['prompts'] as List<dynamic>?)?.cast<String>() ?? const [],
      mcpServers:
          (json['mcpServers'] as List<dynamic>?)?.cast<String>() ?? const [],
      source: SkillSourceExt.fromString(json['source'] as String? ?? 'local'),
      githubUrl: json['githubUrl'] as String?,
      localPath: json['localPath'] as String?,
      isEnabled: json['isEnabled'] as bool? ?? false,
      isInstalled: json['isInstalled'] as bool? ?? false,
      installedAt: json['installedAt'] != null
          ? DateTime.parse(json['installedAt'] as String)
          : null,
      usageCount: json['usageCount'] as int? ?? 0,
      readme: json['readme'] as String?,
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      installCount: json['installCount'] as int? ?? 0,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory Skill.fromJsonString(String jsonStr) {
    return Skill.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
  }

  // ── Factory: from skill.yaml manifest ──────────

  factory Skill.fromManifest(
    Map<String, dynamic> manifest, {
    SkillSource source = SkillSource.github,
    String? githubUrl,
    String? localPath,
  }) {
    return Skill(
      id: manifest['id'] as String,
      name: manifest['name'] as String,
      version: manifest['version'] as String? ?? '1.0.0',
      description: manifest['description'] as String? ?? '',
      author: manifest['author'] as String? ?? 'unknown',
      iconUrl: manifest['icon'] as String?,
      tags: (manifest['tags'] as List<dynamic>?)?.cast<String>() ?? const [],
      actions:
          (manifest['actions'] as List<dynamic>?)?.cast<String>() ?? const [],
      prompts:
          (manifest['prompts'] as List<dynamic>?)?.cast<String>() ?? const [],
      mcpServers:
          (manifest['mcp_servers'] as List<dynamic>?)?.cast<String>() ??
              const [],
      source: source,
      githubUrl: githubUrl,
      localPath: localPath,
    );
  }

  // ── Helpers ────────────────────────────────────

  /// Whether this skill requires MCP servers.
  bool get hasMcpServers => mcpServers.isNotEmpty;

  /// Whether this skill provides actions.
  bool get hasActions => actions.isNotEmpty;

  /// Whether this skill provides prompt templates.
  bool get hasPrompts => prompts.isNotEmpty;

  /// Formatted install count (e.g., "1.2k").
  String get formattedInstallCount {
    if (installCount >= 1000000) {
      return '${(installCount / 1000000).toStringAsFixed(1)}M';
    } else if (installCount >= 1000) {
      return '${(installCount / 1000).toStringAsFixed(1)}k';
    }
    return '$installCount';
  }

  @override
  String toString() => 'Skill($id v$version, source=${source.displayName})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Skill && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

// ═══════════════════════════════════════════════════════════════════════════
// MCP Server Model
// ═══════════════════════════════════════════════════════════════════════════

/// An MCP (Model Context Protocol) server configuration.
///
/// MCP servers extend the agent's capabilities by providing tools
/// that the AI can invoke dynamically.
///
/// Connection types:
/// - stdio: Local process communication (command-based)
/// - sse: Server-Sent Events over HTTP
class McpServer {
  /// Unique identifier
  final String id;

  /// Display name
  final String name;

  /// Connection type: "stdio" or "sse"
  final String type;

  /// For stdio: the command to run (e.g., "npx -y @modelcontextprotocol/server-github")
  final String command;

  /// For sse: the endpoint URL (e.g., "https://mcp.example.com/sse")
  final String? url;

  /// Environment variables for the server process
  final Map<String, dynamic> env;

  /// Whether the server is enabled
  bool isEnabled;

  /// Current runtime status
  McpServerStatus status;

  /// Error message if status is error
  String? errorMessage;

  /// Associated skill IDs that registered this server
  final List<String> skillIds;

  /// When this server was registered
  final DateTime? registeredAt;

  /// Server description
  final String? description;

  /// Server version
  final String? version;

  /// Available tools exposed by this server (populated at runtime)
  final List<McpTool> tools;

  /// Last connection timestamp
  DateTime? lastConnectedAt;

  /// Log messages from the server
  final List<String> logs;

  McpServer({
    required this.id,
    required this.name,
    required this.type,
    required this.command,
    this.url,
    this.env = const {},
    this.isEnabled = false,
    this.status = McpServerStatus.stopped,
    this.errorMessage,
    this.skillIds = const [],
    this.registeredAt,
    this.description,
    this.version,
    this.tools = const [],
    this.lastConnectedAt,
    this.logs = const [],
  });

  // ── Copy ─────────────────────────────────────────

  McpServer copyWith({
    String? id,
    String? name,
    String? type,
    String? command,
    String? url,
    Map<String, dynamic>? env,
    bool? isEnabled,
    McpServerStatus? status,
    String? errorMessage,
    List<String>? skillIds,
    DateTime? registeredAt,
    String? description,
    String? version,
    List<McpTool>? tools,
    DateTime? lastConnectedAt,
    List<String>? logs,
  }) {
    return McpServer(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      command: command ?? this.command,
      url: url ?? this.url,
      env: env ?? Map.unmodifiable(this.env),
      isEnabled: isEnabled ?? this.isEnabled,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      skillIds: skillIds ?? List.unmodifiable(this.skillIds),
      registeredAt: registeredAt ?? this.registeredAt,
      description: description ?? this.description,
      version: version ?? this.version,
      tools: tools ?? List.unmodifiable(this.tools),
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
      logs: logs ?? List.unmodifiable(this.logs),
    );
  }

  // ── JSON Serialization ─────────────────────────

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'command': command,
      'url': url,
      'env': env,
      'isEnabled': isEnabled,
      'status': status.name,
      'errorMessage': errorMessage,
      'skillIds': skillIds,
      'registeredAt': registeredAt?.toIso8601String(),
      'description': description,
      'version': version,
      'tools': tools.map((t) => t.toJson()).toList(),
      'lastConnectedAt': lastConnectedAt?.toIso8601String(),
      'logs': logs,
    };
  }

  factory McpServer.fromJson(Map<String, dynamic> json) {
    return McpServer(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      command: json['command'] as String,
      url: json['url'] as String?,
      env: (json['env'] as Map<String, dynamic>?) ?? const {},
      isEnabled: json['isEnabled'] as bool? ?? false,
      status: McpServerStatus.values.firstWhere(
        (e) => e.name == (json['status'] as String? ?? 'stopped'),
        orElse: () => McpServerStatus.stopped,
      ),
      errorMessage: json['errorMessage'] as String?,
      skillIds:
          (json['skillIds'] as List<dynamic>?)?.cast<String>() ?? const [],
      registeredAt: json['registeredAt'] != null
          ? DateTime.parse(json['registeredAt'] as String)
          : null,
      description: json['description'] as String?,
      version: json['version'] as String?,
      tools: (json['tools'] as List<dynamic>?)
              ?.map((e) => McpTool.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      lastConnectedAt: json['lastConnectedAt'] != null
          ? DateTime.parse(json['lastConnectedAt'] as String)
          : null,
      logs: (json['logs'] as List<dynamic>?)?.cast<String>() ?? const [],
    );
  }

  // ── Factory: from skill manifest mcp_servers entry ──

  factory McpServer.fromManifestEntry(
    Map<String, dynamic> entry, {
    String? skillId,
  }) {
    return McpServer(
      id: entry['id'] as String,
      name: entry['name'] as String,
      type: entry['type'] as String? ?? 'stdio',
      command: entry['command'] as String? ?? '',
      url: entry['url'] as String?,
      env: (entry['env'] as Map<String, dynamic>?) ?? const {},
      description: entry['description'] as String?,
      version: entry['version'] as String? ?? '1.0.0',
      skillIds: skillId != null ? [skillId] : const [],
      registeredAt: DateTime.now(),
    );
  }

  // ── Helpers ────────────────────────────────────

  /// Whether this is a stdio-type server.
  bool get isStdio => type == 'stdio';

  /// Whether this is an sse-type server.
  bool get isSse => type == 'sse';

  /// Whether the server is currently running.
  bool get isRunning => status == McpServerStatus.running;

  /// Whether the server has an error.
  bool get hasError => status == McpServerStatus.error;

  /// Whether the server has tools registered.
  bool get hasTools => tools.isNotEmpty;

  @override
  String toString() => 'McpServer($id, type=$type, status=${status.name})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is McpServer && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

// ═══════════════════════════════════════════════════════════════════════════
// MCP Tool Model
// ═══════════════════════════════════════════════════════════════════════════

/// A tool exposed by an MCP server.
class McpTool {
  /// Tool name/identifier
  final String name;

  /// Human-readable description of what the tool does
  final String description;

  /// Input schema (JSON Schema)
  final Map<String, dynamic> inputSchema;

  McpTool({
    required this.name,
    required this.description,
    this.inputSchema = const {},
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'inputSchema': inputSchema,
    };
  }

  factory McpTool.fromJson(Map<String, dynamic> json) {
    return McpTool(
      name: json['name'] as String,
      description: json['description'] as String,
      inputSchema:
          (json['inputSchema'] as Map<String, dynamic>?) ?? const {},
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Skill Install Log Entry
// ═══════════════════════════════════════════════════════════════════════════

/// A log entry for skill installation/update/uninstall operations.
class SkillInstallLog {
  final String skillId;
  final String operation; // install, update, uninstall, enable, disable
  final DateTime timestamp;
  final bool success;
  final String? error;

  SkillInstallLog({
    required this.skillId,
    required this.operation,
    required this.timestamp,
    required this.success,
    this.error,
  });

  Map<String, dynamic> toJson() {
    return {
      'skillId': skillId,
      'operation': operation,
      'timestamp': timestamp.toIso8601String(),
      'success': success,
      'error': error,
    };
  }

  factory SkillInstallLog.fromJson(Map<String, dynamic> json) {
    return SkillInstallLog(
      skillId: json['skillId'] as String,
      operation: json['operation'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      success: json['success'] as bool,
      error: json['error'] as String?,
    );
  }
}
