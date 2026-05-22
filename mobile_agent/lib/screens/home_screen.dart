import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/evidence/action_evidence_store.dart';
import '../core/evidence/action_runner.dart';
import '../core/evidence/evidence_model.dart';
import 'agent_dashboard_screen.dart';
import 'api_usage_screen.dart';
import 'device_telemetry_screen.dart';
import 'downloads_shared_folders_screen.dart';
import 'editor_screen.dart';
import 'github_repo_hub_screen.dart';
import 'github_screen.dart';
import 'hook_registry_screen.dart';
import 'memory_manager_screen.dart';
import 'mcp_manager_screen.dart';
import 'role_manager_screen.dart';
import 'skill_manager_screen.dart';
import '../services/feature_flags_service.dart';
import '../services/github_deep_service.dart';
import '../services/github_pages_service.dart';
import '../services/github_repo_hub_service.dart';
import '../services/html_publish_readiness_service.dart';
import '../services/role_library_service.dart';
import '../services/runtime_manager.dart';
import '../services/runtime_actions.dart';
import '../services/runtime_provider.dart';
import '../services/agent_loop_controller.dart';
import '../services/device_telemetry_service.dart';
import '../services/skill_manager_service.dart';
import '../services/termux_service.dart';
import '../services/token_usage_service.dart';
import '../services/tool_call_adapter.dart';
import '../services/voice_service.dart';

enum _ApiFlavor { openAi, anthropic }

enum _ProviderPreset { mimo, deepSeek, anthropic, openAi, custom }

enum _HealthState { unknown, checking, healthy, failed }

enum _HomeTab { control, ai, ship, guard, insight }

enum _CapabilityStatus { ready, needsConfig, local, preview }

enum _AgentStepState { queued, running, done, failed }

enum _LocalToolEventKind {
  system,
  thought,
  toolCall,
  observation,
  fileWrite,
  diff,
  preview,
  finalAnswer,
  error,
}

enum _ModuleAction {
  aiChat,
  apiConfig,
  healthCheck,
  webDemo,
  githubTest,
  diary,
  toolLab,
  termuxCheck,
  newFile,
  snippet,
  project,
  terminal,
  deepDive,
  build,
  githubRepoHub,
  larkCli,
  tokenUsage,
  deviceTelemetry,
  downloadsShared,
  activityCenter,
  inspect,
}

const _bg = Color(0xFFF7FAFF);
const _panel = Color(0xFFFFFFFF);
const _panelSoft = Color(0xFFF0F5FF);
const _line = Color(0xFFDDE7F7);
const _text = Color(0xFF0B1020);
const _muted = Color(0xFF536079);
const _faint = Color(0xFF8B97AD);
const _mint = Color(0xFF0B9B7E);
const _cyan = Color(0xFF16B9C7);
const _amber = Color(0xFFB7791F);
const _rose = Color(0xFFE0526E);
const _lime = Color(0xFF4F8F2D);
const _violet = Color(0xFF7557E8);
const _blue = Color(0xFF2555FF);
const _defaultBaseUrl = 'https://token-plan-cn.xiaomimimo.com/anthropic';
const _defaultModel = 'mimo-v2.5-pro';
const _managedProviderEnabled = bool.fromEnvironment('MOBILECODE_MANAGED_PROVIDER');
const _managedBaseUrl = String.fromEnvironment(
  'MOBILECODE_MANAGED_BASE_URL',
  defaultValue: _defaultBaseUrl,
);
const _managedModel = String.fromEnvironment(
  'MOBILECODE_MANAGED_MODEL',
  defaultValue: _defaultModel,
);
const _managedApiKey = String.fromEnvironment('MOBILECODE_MANAGED_API_KEY');
const _managedDeepSeekProviderEnabled = bool.fromEnvironment('MOBILECODE_MANAGED_DEEPSEEK_PROVIDER');
const _managedDeepSeekBaseUrl = String.fromEnvironment(
  'MOBILECODE_MANAGED_DEEPSEEK_BASE_URL',
  defaultValue: 'https://api.deepseek.com',
);
const _managedDeepSeekModel = String.fromEnvironment(
  'MOBILECODE_MANAGED_DEEPSEEK_MODEL',
  defaultValue: 'deepseek-v4-flash',
);
const _managedDeepSeekApiKey = String.fromEnvironment('MOBILECODE_MANAGED_DEEPSEEK_API_KEY');
const _managedRelayUrl = String.fromEnvironment('MOBILECODE_MANAGED_RELAY_URL');
const _managedRelayToken = String.fromEnvironment('MOBILECODE_MANAGED_RELAY_TOKEN');
const _demo2048Url = 'https://harzva.github.io/mobilecode/demo/2048/';
const _githubTestUrl = 'https://harzva.github.io/mobilecode/github-test/';
const _releaseUrl = 'https://github.com/Harzva/mobilecode/releases/tag/v0.1.30';
const _androidSmokeRunUrl = 'https://github.com/Harzva/mobilecode/actions/workflows/android-app-test.yml';
const _iosSimulatorRunUrl = 'https://github.com/Harzva/mobilecode/actions/workflows/ios-simulator.yml';
const _releaseBuildLabel = 'v0.1.30+49';
const _systemToolsChannel = MethodChannel('mobilecode/system_tools');
const _mobileCodeProjectsFolderName = 'mobilecode_projects';
const _browserOpenModeSystem = 'systemDefault';
const _browserOpenModeInApp = 'inAppBrowser';
const _rrModeAvatarAsset = 'assets/role_avatars/avatar-batch2-24-rounded-icon.svg';

String _normalizeBrandTheme(String value) {
  return value == 'claudeYellow' ? 'claudeYellow' : 'codexBlue';
}

String _normalizeBrowserOpenMode(String? value) {
  return value == _browserOpenModeInApp ? _browserOpenModeInApp : _browserOpenModeSystem;
}

String _browserOpenModeLabel(String value) {
  return _normalizeBrowserOpenMode(value) == _browserOpenModeInApp ? 'App 内浏览器优先' : '系统默认浏览器';
}

TokenUsageSnapshot _providerUsageFromBody(_ApiFlavor flavor, String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return flavor == _ApiFlavor.anthropic
          ? TokenUsageService.parseAnthropicUsage(decoded)
          : TokenUsageService.parseOpenAiUsage(decoded);
    }
  } catch (_) {
    // Providers without usage metadata fall back to local estimation.
  }
  return TokenUsageSnapshot.empty;
}

String? runtimeFailureKindHint(RuntimeTaskFailureKind kind) {
  switch (kind) {
    case RuntimeTaskFailureKind.none:
      return null;
    case RuntimeTaskFailureKind.timeout:
      return 'Increase the timeout, inspect recent logs, then retry or move the task to cloud runtime.';
    case RuntimeTaskFailureKind.cancelled:
      return 'The task was stopped intentionally. Retry the same taskId when ready.';
    case RuntimeTaskFailureKind.dependencyMissing:
      return 'Install the missing dependency in Helper or Termux before retrying.';
    case RuntimeTaskFailureKind.commandBlocked:
      return 'Use a structured runtime action or confirm the command before running it.';
    case RuntimeTaskFailureKind.cwdOutsideWorkspace:
      return 'Move the project under the MobileCode workspace and retry.';
    case RuntimeTaskFailureKind.authFailed:
      return 'Check the provider token, GitHub token, or Helper auth token.';
    case RuntimeTaskFailureKind.processFailed:
      return 'Open task details, copy the failure summary, fix the command error, then retry.';
    case RuntimeTaskFailureKind.runtimeLost:
      return 'Restart MobileCode Helper or Termux daemon, refresh runtime status, then retry.';
    case RuntimeTaskFailureKind.unknown:
      return 'Check task logs and runtime health before retrying.';
  }
}

class _ProbeResult {
  const _ProbeResult({
    required this.uri,
    required this.statusCode,
    required this.latencyMs,
    required this.message,
  });

  final Uri uri;
  final int? statusCode;
  final int latencyMs;
  final String message;

  bool get isHealthy => statusCode != null && statusCode! >= 200 && statusCode! < 300;
}

class _CapabilityLayer {
  const _CapabilityLayer({
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.capabilities,
  });

  final String name;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<_Capability> capabilities;

  int get serviceCount {
    final services = <String>{};
    for (final capability in capabilities) {
      services.addAll(capability.services);
    }
    return services.length;
  }
}

class _Capability {
  const _Capability({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.status,
    required this.services,
    required this.actions,
    required this.primaryAction,
    this.surface = 'Console panel',
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final _CapabilityStatus status;
  final List<String> services;
  final List<String> actions;
  final _ModuleAction primaryAction;
  final String surface;
}

class _ActivityLog {
  const _ActivityLog({
    required this.title,
    required this.detail,
    required this.icon,
    required this.color,
    required this.time,
  });

  final String title;
  final String detail;
  final IconData icon;
  final Color color;
  final DateTime time;
}

class _DraftFile {
  const _DraftFile({
    required this.name,
    required this.language,
    required this.createdAt,
  });

  final String name;
  final String language;
  final DateTime createdAt;
}

class _SnippetDraft {
  const _SnippetDraft({
    required this.title,
    required this.language,
    required this.createdAt,
  });

  final String title;
  final String language;
  final DateTime createdAt;
}

class _ChatTurn {
  const _ChatTurn({
    required this.role,
    required this.content,
    required this.time,
    this.bookmarked = false,
  });

  final String role;
  final String content;
  final DateTime time;
  final bool bookmarked;

  _ChatTurn copyWith({
    String? role,
    String? content,
    DateTime? time,
    bool? bookmarked,
  }) {
    return _ChatTurn(
      role: role ?? this.role,
      content: content ?? this.content,
      time: time ?? this.time,
      bookmarked: bookmarked ?? this.bookmarked,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'role': role,
      'content': content,
      'time': time.toIso8601String(),
      'bookmarked': bookmarked,
    };
  }

  factory _ChatTurn.fromJson(Map<String, dynamic> json) {
    return _ChatTurn(
      role: json['role'] as String? ?? 'user',
      content: json['content'] as String? ?? '',
      time: DateTime.tryParse(json['time'] as String? ?? '') ?? DateTime.now(),
      bookmarked: json['bookmarked'] as bool? ?? false,
    );
  }
}

class _ChatSession {
  const _ChatSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.turns,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<_ChatTurn> turns;

  _ChatSession copyWith({
    String? title,
    DateTime? updatedAt,
    List<_ChatTurn>? turns,
  }) {
    return _ChatSession(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      turns: turns ?? this.turns,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'turns': turns.map((turn) => turn.toJson()).toList(),
    };
  }

  factory _ChatSession.fromJson(Map<String, dynamic> json) {
    return _ChatSession(
      id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: json['title'] as String? ?? 'Untitled chat',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
      turns: ((json['turns'] as List?) ?? const [])
          .whereType<Map>()
          .map((turn) => _ChatTurn.fromJson(Map<String, dynamic>.from(turn)))
          .toList(),
    );
  }
}

class _DiaryEntry {
  const _DiaryEntry({
    required this.title,
    required this.body,
    required this.time,
  });

  final String title;
  final String body;
  final DateTime time;

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'body': body,
      'time': time.toIso8601String(),
    };
  }

  factory _DiaryEntry.fromJson(Map<String, dynamic> json) {
    return _DiaryEntry(
      title: json['title'] as String? ?? 'Untitled',
      body: json['body'] as String? ?? '',
      time: DateTime.tryParse(json['time'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

class _ToolProbe {
  const _ToolProbe({
    required this.name,
    required this.detail,
    required this.icon,
    required this.action,
  });

  final String name;
  final String detail;
  final IconData icon;
  final String action;
}

class _ToolProbeResult {
  const _ToolProbeResult({
    required this.name,
    required this.ok,
    required this.message,
  });

  final String name;
  final bool ok;
  final String message;
}

class _RootProbeResult {
  const _RootProbeResult({
    required this.available,
    required this.detail,
  });

  final bool available;
  final String detail;

  factory _RootProbeResult.fromMap(Map<dynamic, dynamic> map) {
    return _RootProbeResult(
      available: map['available'] == true,
      detail: map['detail'] as String? ?? 'Root status returned without detail.',
    );
  }
}

class _HelperDaemonProbeResult {
  const _HelperDaemonProbeResult({
    required this.ready,
    required this.detail,
  });

  final bool ready;
  final String detail;
}

class _AgentTraceStep {
  _AgentTraceStep({
    required this.title,
    required this.detail,
    required this.icon,
    this.avatarAsset,
    this.toolName,
    this.details = const {},
    this.traceAction = MobileCodeAction.traceParseInstruction,
    String? evidenceId,
    this.state = _AgentStepState.queued,
    DateTime? startedAt,
    this.finishedAt,
  })  : evidenceId = evidenceId ?? generateEvidenceId(),
        startedAt = startedAt ?? DateTime.now();

  final String title;
  final String detail;
  final IconData icon;
  final String? avatarAsset;
  final String? toolName;
  final Map<String, String> details;
  final MobileCodeAction traceAction;
  final String evidenceId;
  final _AgentStepState state;
  final DateTime startedAt;
  final DateTime? finishedAt;
  ActionEvidence? evidence;

  _AgentTraceStep copyWith({
    String? title,
    String? detail,
    IconData? icon,
    String? avatarAsset,
    String? toolName,
    Map<String, String>? details,
    MobileCodeAction? traceAction,
    String? evidenceId,
    _AgentStepState? state,
    DateTime? startedAt,
    DateTime? finishedAt,
    ActionEvidence? evidence,
  }) {
    final next = _AgentTraceStep(
      title: title ?? this.title,
      detail: detail ?? this.detail,
      icon: icon ?? this.icon,
      avatarAsset: avatarAsset ?? this.avatarAsset,
      toolName: toolName ?? this.toolName,
      details: details ?? this.details,
      traceAction: traceAction ?? this.traceAction,
      evidenceId: evidenceId ?? this.evidenceId,
      state: state ?? this.state,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
    );
    next.evidence = evidence ?? this.evidence;
    return next;
  }
}

class _LocalToolEvent {
  const _LocalToolEvent({
    required this.kind,
    required this.title,
    required this.detail,
    required this.time,
    this.toolName,
    this.path,
    this.durationMs,
    this.ok = true,
  });

  final _LocalToolEventKind kind;
  final String title;
  final String detail;
  final DateTime time;
  final String? toolName;
  final String? path;
  final int? durationMs;
  final bool ok;

  Map<String, dynamic> toJson() {
    return {
      'kind': kind.name,
      'title': title,
      'detail': detail,
      'toolName': toolName,
      'path': path,
      'durationMs': durationMs,
      'ok': ok,
      'time': time.toIso8601String(),
    };
  }
}

class _LocalToolSpec {
  const _LocalToolSpec({
    required this.name,
    required this.description,
    required this.surface,
    required this.icon,
    required this.color,
    required this.risk,
  });

  final String name;
  final String description;
  final String surface;
  final IconData icon;
  final Color color;
  final String risk;
}

class _AndroidCommandSpec {
  const _AndroidCommandSpec({
    required this.category,
    required this.commands,
    required this.support,
    required this.mobileCodePath,
    required this.note,
    required this.color,
    required this.icon,
  });

  final String category;
  final String commands;
  final String support;
  final String mobileCodePath;
  final String note;
  final Color color;
  final IconData icon;
}

const _localToolSpecs = [
  _LocalToolSpec(
    name: 'list_files',
    description: 'Inspect app-owned project folders before writing.',
    surface: 'Android app documents',
    icon: Icons.folder_open_outlined,
    color: _mint,
    risk: 'read-only',
  ),
  _LocalToolSpec(
    name: 'write_file',
    description: 'Write generated code with a temp-file rename.',
    surface: 'Android app documents',
    icon: Icons.edit_note_outlined,
    color: _cyan,
    risk: 'guarded',
  ),
  _LocalToolSpec(
    name: 'read_file',
    description: 'Read generated files back for preview and copy.',
    surface: 'Android app documents',
    icon: Icons.description_outlined,
    color: _blue,
    risk: 'read-only',
  ),
  _LocalToolSpec(
    name: 'move_file',
    description: 'Move or rename one file inside the app workspace.',
    surface: 'Android app documents',
    icon: Icons.drive_file_move_outline,
    color: _amber,
    risk: 'guarded',
  ),
  _LocalToolSpec(
    name: 'preview_webview',
    description: 'Load HTML/CSS/JS into the in-app Android WebView.',
    surface: 'Android WebView',
    icon: Icons.preview_outlined,
    color: _violet,
    risk: 'local',
  ),
  _LocalToolSpec(
    name: 'web_search',
    description: 'Read compact public web references through the managed relay.',
    surface: 'Relay web tool',
    icon: Icons.travel_explore_outlined,
    color: _amber,
    risk: 'read-only network',
  ),
  _LocalToolSpec(
    name: 'fetch_url',
    description: 'Fetch one public HTTPS page summary through the managed relay.',
    surface: 'Relay web tool',
    icon: Icons.link_outlined,
    color: _cyan,
    risk: 'read-only network',
  ),
  _LocalToolSpec(
    name: 'preview_snapshot',
    description: 'Save WebView preview metadata as ActionEvidence.',
    surface: 'ActionEvidence',
    icon: Icons.photo_camera_back_outlined,
    color: _blue,
    risk: 'local evidence',
  ),
  _LocalToolSpec(
    name: 'termux_probe',
    description: 'Check local runtime providers for shell-like mobile builds.',
    surface: 'Runtime provider bridge',
    icon: Icons.terminal_outlined,
    color: _lime,
    risk: 'controlled shell',
  ),
  _LocalToolSpec(
    name: 'github_connect',
    description: 'Open the GitHub Pages token/repo connectivity tester.',
    surface: 'GitHub API',
    icon: Icons.hub_outlined,
    color: _amber,
    risk: 'network',
  ),
];

const _providerNativeToolSpecs = [
  _LocalToolSpec(
    name: 'list_files',
    description: 'List workspace files. This is the safe provider-native replacement for ls/find.',
    surface: 'ActionRunner',
    icon: Icons.folder_open_outlined,
    color: _blue,
    risk: 'read-only',
  ),
  _LocalToolSpec(
    name: 'find_files',
    description: 'Find workspace files by name or glob. This is the safe replacement for find/fd.',
    surface: 'ActionRunner',
    icon: Icons.manage_search_outlined,
    color: _blue,
    risk: 'read-only',
  ),
  _LocalToolSpec(
    name: 'grep_files',
    description: 'Search text inside bounded workspace files. This is the safe replacement for grep/rg.',
    surface: 'ActionRunner',
    icon: Icons.search_outlined,
    color: _cyan,
    risk: 'read-only',
  ),
  _LocalToolSpec(
    name: 'web_search',
    description: 'Let the model ask for compact public web references through the managed relay.',
    surface: 'Relay read',
    icon: Icons.travel_explore_outlined,
    color: _amber,
    risk: 'read-only',
  ),
  _LocalToolSpec(
    name: 'fetch_url',
    description: 'Fetch and summarize one public HTTPS URL; local/private URLs are blocked.',
    surface: 'Relay read',
    icon: Icons.link_outlined,
    color: _cyan,
    risk: 'read-only',
  ),
  _LocalToolSpec(
    name: 'write_file',
    description: 'Write complete file content inside the MobileCode workspace via ActionRunner.',
    surface: 'ActionRunner',
    icon: Icons.edit_note_outlined,
    color: _mint,
    risk: 'guarded write',
  ),
  _LocalToolSpec(
    name: 'read_file',
    description: 'Read a bounded preview of a workspace file and return it as model observation.',
    surface: 'ActionRunner',
    icon: Icons.description_outlined,
    color: _blue,
    risk: 'read-only',
  ),
  _LocalToolSpec(
    name: 'move_file',
    description: 'Move or rename one workspace file. This is the safe replacement for mv.',
    surface: 'ActionRunner',
    icon: Icons.drive_file_move_outline,
    color: _amber,
    risk: 'guarded move',
  ),
  _LocalToolSpec(
    name: 'apply_patch',
    description: 'Apply a small unified diff inside the workspace with snapshot evidence.',
    surface: 'ActionRunner',
    icon: Icons.difference_outlined,
    color: _amber,
    risk: 'bounded write',
  ),
  _LocalToolSpec(
    name: 'preview_html',
    description: 'Prepare an in-app WebView preview from a workspace HTML file or inline HTML.',
    surface: 'WebView',
    icon: Icons.preview_outlined,
    color: _violet,
    risk: 'local preview',
  ),
  _LocalToolSpec(
    name: 'preview_snapshot',
    description: 'Record preview metadata/DOM evidence; this is not a native bitmap screenshot.',
    surface: 'ActionEvidence',
    icon: Icons.photo_camera_back_outlined,
    color: _cyan,
    risk: 'local evidence',
  ),
  _LocalToolSpec(
    name: 'report_result',
    description: 'Finish the loop with a concise status, summary, evidence IDs, and recovery notes.',
    surface: 'Agent Loop',
    icon: Icons.fact_check_outlined,
    color: _mint,
    risk: 'no execution',
  ),
];

const _androidCommandSpecs = [
  _AndroidCommandSpec(
    category: 'File inspect',
    commands: 'pwd, ls, dir, find, fd',
    support: 'Supported',
    mobileCodePath: 'list_files / find_files',
    note: 'Lists and finds only inside the MobileCode workspace; no arbitrary filesystem traversal.',
    color: _mint,
    icon: Icons.folder_open_outlined,
  ),
  _AndroidCommandSpec(
    category: 'File read/write',
    commands: 'cat, head, tail, less, more, echo >',
    support: 'Supported',
    mobileCodePath: 'read_file / write_file',
    note: 'Reads bounded previews and writes complete files through ActionRunner evidence.',
    color: _mint,
    icon: Icons.description_outlined,
  ),
  _AndroidCommandSpec(
    category: 'Text search',
    commands: 'grep, rg, ag, awk, sed',
    support: 'Supported',
    mobileCodePath: 'grep_files',
    note: 'Plain text grep-style search with result and file-size bounds; no raw shell.',
    color: _mint,
    icon: Icons.manage_search_outlined,
  ),
  _AndroidCommandSpec(
    category: 'File metadata',
    commands: 'stat, file, wc, sort, uniq, cut, tr',
    support: 'Partial',
    mobileCodePath: 'list_files metadata',
    note: 'list_files returns path/type/size/modifiedAt; detailed text transforms are not exposed yet.',
    color: _amber,
    icon: Icons.info_outline,
  ),
  _AndroidCommandSpec(
    category: 'Move / rename',
    commands: 'mv',
    support: 'Supported',
    mobileCodePath: 'move_file',
    note: 'File-only move inside workspace; destination must include the filename.',
    color: _mint,
    icon: Icons.drive_file_move_outline,
  ),
  _AndroidCommandSpec(
    category: 'Patch / diff apply',
    commands: 'patch, git apply',
    support: 'Supported',
    mobileCodePath: 'apply_patch',
    note: 'Unified diff only, workspace-limited, deletion/binary/outside paths blocked, snapshots recorded.',
    color: _mint,
    icon: Icons.difference_outlined,
  ),
  _AndroidCommandSpec(
    category: 'Copy / mkdir',
    commands: 'cp, mkdir, touch',
    support: 'Partial',
    mobileCodePath: 'write_file creates parent folders',
    note: 'No generic copy command yet; safe copy_file/mkdir can be added later.',
    color: _amber,
    icon: Icons.create_new_folder_outlined,
  ),
  _AndroidCommandSpec(
    category: 'Delete',
    commands: 'rm, rmdir',
    support: 'Blocked',
    mobileCodePath: 'not exposed',
    note: 'Deletion is intentionally not available to Agent Loop yet.',
    color: _rose,
    icon: Icons.delete_outline,
  ),
  _AndroidCommandSpec(
    category: 'Network read',
    commands: 'curl, wget, fetch',
    support: 'Supported',
    mobileCodePath: 'fetch_url / web_search',
    note: 'Relay-backed public HTTPS only; local/private URLs are blocked.',
    color: _mint,
    icon: Icons.public_outlined,
  ),
  _AndroidCommandSpec(
    category: 'Network diagnostics',
    commands: 'ping, traceroute, nslookup, dig, host, nc',
    support: 'Blocked',
    mobileCodePath: 'not exposed',
    note: 'Useful in Termux, but not safe as provider-native tools in the APK.',
    color: _rose,
    icon: Icons.network_check_outlined,
  ),
  _AndroidCommandSpec(
    category: 'Preview evidence',
    commands: 'browser open, screenshot-like check',
    support: 'Supported',
    mobileCodePath: 'preview_html / preview_snapshot',
    note: 'Snapshot is metadata/DOM evidence, not a native bitmap screenshot.',
    color: _mint,
    icon: Icons.preview_outlined,
  ),
  _AndroidCommandSpec(
    category: 'Environment inspect',
    commands: 'whoami, id, uname, env, printenv, date, uptime',
    support: 'Runtime only',
    mobileCodePath: 'Runtime providers',
    note: 'Can be surfaced through diagnostics later; not model-callable today.',
    color: _amber,
    icon: Icons.badge_outlined,
  ),
  _AndroidCommandSpec(
    category: 'Storage inspect',
    commands: 'df, du, free, vmstat',
    support: 'Runtime only',
    mobileCodePath: 'Runtime providers',
    note: 'Possible through Termux/Helper diagnostics; not in provider-native AgentLoop.',
    color: _amber,
    icon: Icons.storage_outlined,
  ),
  _AndroidCommandSpec(
    category: 'Process / Android system',
    commands: 'ps, top, kill, pm, am, dumpsys',
    support: 'Blocked',
    mobileCodePath: 'not exposed',
    note: 'These require runtime permissions and are not provider-native Agent tools.',
    color: _rose,
    icon: Icons.memory_outlined,
  ),
  _AndroidCommandSpec(
    category: 'Android package / activity',
    commands: 'pm, am, cmd, settings, dumpsys, logcat',
    support: 'Blocked',
    mobileCodePath: 'not exposed',
    note: 'Android system APIs need explicit app/runtime permission design before model access.',
    color: _rose,
    icon: Icons.android_outlined,
  ),
  _AndroidCommandSpec(
    category: 'Git / release',
    commands: 'git status/add/commit/push',
    support: 'Not AgentLoop',
    mobileCodePath: 'GitHub screens / CI only',
    note: 'No provider-native Git push or publishing in this safety profile.',
    color: _faint,
    icon: Icons.hub_outlined,
  ),
  _AndroidCommandSpec(
    category: 'Build / package',
    commands: 'npm, yarn, pnpm, pip, cargo, go, dart, flutter, gradle, make',
    support: 'Runtime only',
    mobileCodePath: 'Runtime providers',
    note: 'Depends on Helper/Termux/CI; not exposed as free-form model tools.',
    color: _amber,
    icon: Icons.terminal_outlined,
  ),
];

String _normalizedBaseUrl(String baseUrl) {
  return baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
}

String _savedOrDefault(String? value, String fallback) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? fallback : trimmed;
}

_ApiFlavor _detectApiFlavor(String baseUrl, String model) {
  final probe = '$baseUrl $model'.toLowerCase();
  if (probe.contains('anthropic') ||
      probe.contains('claude') ||
      probe.contains('mimo-')) {
    return _ApiFlavor.anthropic;
  }
  return _ApiFlavor.openAi;
}

_ProviderPreset _detectProviderPreset(String baseUrl, String model) {
  final probe = '$baseUrl $model'.toLowerCase();
  if (probe.contains('xiaomimimo') || probe.contains('mimo-')) {
    return _ProviderPreset.mimo;
  }
  if (probe.contains('deepseek')) {
    return _ProviderPreset.deepSeek;
  }
  if (probe.contains('anthropic') || probe.contains('claude')) {
    return _ProviderPreset.anthropic;
  }
  if (probe.contains('openai') || probe.contains('gpt-')) {
    return _ProviderPreset.openAi;
  }
  return _ProviderPreset.custom;
}

String _providerPresetLabel(_ProviderPreset preset) {
  return switch (preset) {
    _ProviderPreset.mimo => 'Mimo',
    _ProviderPreset.deepSeek => 'DeepSeek v4',
    _ProviderPreset.anthropic => 'Anthropic',
    _ProviderPreset.openAi => 'OpenAI',
    _ProviderPreset.custom => 'Custom',
  };
}

String _providerPresetBaseUrl(_ProviderPreset preset) {
  return switch (preset) {
    _ProviderPreset.mimo => _defaultBaseUrl,
    _ProviderPreset.deepSeek => 'https://api.deepseek.com',
    _ProviderPreset.anthropic => 'https://api.anthropic.com',
    _ProviderPreset.openAi => 'https://api.openai.com/v1',
    _ProviderPreset.custom => '',
  };
}

String _providerPresetModel(_ProviderPreset preset) {
  return switch (preset) {
    _ProviderPreset.mimo => _defaultModel,
    _ProviderPreset.deepSeek => 'deepseek-v4-flash',
    _ProviderPreset.anthropic => 'claude-3-5-sonnet-latest',
    _ProviderPreset.openAi => 'gpt-4o-mini',
    _ProviderPreset.custom => '',
  };
}

bool _managedProviderPresetAvailable(_ProviderPreset preset) {
  return switch (preset) {
    _ProviderPreset.mimo =>
      _managedProviderEnabled && (_managedApiKey.trim().isNotEmpty || _managedRelayUrl.trim().isNotEmpty),
    _ProviderPreset.deepSeek =>
      _managedDeepSeekProviderEnabled && (_managedDeepSeekApiKey.trim().isNotEmpty || _managedRelayUrl.trim().isNotEmpty),
    _ => false,
  };
}

String _managedProviderBaseUrl(_ProviderPreset preset) {
  return switch (preset) {
    _ProviderPreset.deepSeek => _managedDeepSeekBaseUrl,
    _ => _managedBaseUrl,
  };
}

String _managedProviderModel(_ProviderPreset preset) {
  return switch (preset) {
    _ProviderPreset.deepSeek => _managedDeepSeekModel,
    _ => _managedModel,
  };
}

String _managedProviderApiKey(_ProviderPreset preset) {
  return switch (preset) {
    _ProviderPreset.deepSeek => _managedDeepSeekApiKey,
    _ => _managedApiKey,
  };
}

List<_ProviderPreset> _availableManagedProviderPresets() {
  return [
    if (_managedProviderPresetAvailable(_ProviderPreset.mimo)) _ProviderPreset.mimo,
    if (_managedProviderPresetAvailable(_ProviderPreset.deepSeek)) _ProviderPreset.deepSeek,
  ];
}

_ProviderPreset _providerPresetFromName(String? value, {_ProviderPreset fallback = _ProviderPreset.mimo}) {
  for (final preset in _ProviderPreset.values) {
    if (preset.name == value) return preset;
  }
  return fallback;
}

_ProviderPreset _firstManagedProviderPreset() {
  final available = _availableManagedProviderPresets();
  return available.isEmpty ? _ProviderPreset.custom : available.first;
}

Uri _parseBaseUrl(String baseUrl) {
  final uri = Uri.parse(_normalizedBaseUrl(baseUrl));
  if (!uri.hasScheme || uri.host.isEmpty) {
    throw const FormatException('Invalid URL');
  }
  return uri;
}

Uri _openAiChatUri(String baseUrl) {
  final normalized = _normalizedBaseUrl(baseUrl);
  final uri = _parseBaseUrl(normalized);
  if (normalized.endsWith('/chat/completions')) return uri;
  if (normalized.endsWith('/v1')) return Uri.parse('$normalized/chat/completions');
  if (normalized.endsWith('/beta')) return Uri.parse('$normalized/chat/completions');
  return Uri.parse('$normalized/chat/completions');
}

Uri _anthropicMessagesUri(String baseUrl) {
  final normalized = _normalizedBaseUrl(baseUrl);
  final uri = _parseBaseUrl(normalized);
  if (normalized.endsWith('/v1/messages') || normalized.endsWith('/messages')) {
    return uri;
  }
  if (normalized.endsWith('/v1')) {
    return Uri.parse('$normalized/messages');
  }
  return Uri.parse('$normalized/v1/messages');
}

String _chatEndpointLabel(String baseUrl, _ApiFlavor flavor) {
  return switch (flavor) {
    _ApiFlavor.anthropic => _anthropicMessagesUri(baseUrl).toString(),
    _ApiFlavor.openAi => _openAiChatUri(baseUrl).toString(),
  };
}

String _compact(String value, {int limit = 800}) {
  final trimmed = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (trimmed.length <= limit) return trimmed;
  return '${trimmed.substring(0, limit)}...';
}

String _friendlySocketError(SocketException error) {
  final raw = error.message.trim().isEmpty ? error.toString() : error.message.trim();
  final lower = raw.toLowerCase();
  if (lower.contains('failed host lookup') ||
      lower.contains('no address associated') ||
      lower.contains('temporary failure in name resolution')) {
    return '$raw. Network/DNS/proxy issue: the device cannot resolve the provider host, so the token was not checked.';
  }
  return raw;
}

List<String> _chunkText(String value, int chunkSize) {
  final chunks = <String>[];
  for (var offset = 0; offset < value.length; offset += chunkSize) {
    final end = offset + chunkSize > value.length ? value.length : offset + chunkSize;
    chunks.add(value.substring(offset, end));
  }
  return chunks;
}

String _clockLabel(DateTime time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  final second = time.second.toString().padLeft(2, '0');
  return '$hour:$minute:$second';
}

String _sessionTurnLabel(_ChatSession session) {
  final messages = session.turns.where((turn) => turn.content.trim().isNotEmpty).length;
  if (messages == 0) return 'Ready to start';
  final userMessages = session.turns.where((turn) => turn.role == 'user' && turn.content.trim().isNotEmpty).length;
  final assistantMessages = session.turns.where((turn) => turn.role == 'assistant' && turn.content.trim().isNotEmpty).length;
  if (userMessages > 0 && assistantMessages > 0) {
    return '$userMessages prompts · $assistantMessages replies';
  }
  return messages == 1 ? '1 message' : '$messages messages';
}

Future<Directory> _mobileCodeProjectsRootDirectory() async {
  final directory = await getApplicationDocumentsDirectory();
  final root = Directory(p.join(directory.path, _mobileCodeProjectsFolderName));
  await root.create(recursive: true);
  return root;
}

String _projectDirectoryForArtifact(String path) => p.dirname(path);

Future<String?> _findGitRootForPath(String path) async {
  var current = path;
  try {
    if (!await FileSystemEntity.isDirectory(current)) {
      current = p.dirname(current);
    }
  } on Object {
    current = p.dirname(current);
  }

  var directory = Directory(current);
  for (var depth = 0; depth < 8; depth++) {
    if (await Directory(p.join(directory.path, '.git')).exists()) {
      return directory.path;
    }
    final parent = directory.parent;
    if (p.equals(parent.path, directory.path)) break;
    directory = parent;
  }
  return null;
}

String _workspaceRelativePath(String path, String workspaceRoot) {
  try {
    final relative = p.relative(path, from: workspaceRoot);
    return relative.startsWith('..') ? path : relative;
  } on Object {
    return path;
  }
}

Future<bool> _launchUrlWithBrowserMode(Uri uri, String browserOpenMode) async {
  final prefersInApp = _normalizeBrowserOpenMode(browserOpenMode) == _browserOpenModeInApp &&
      (uri.scheme == 'http' || uri.scheme == 'https');
  final firstMode = prefersInApp ? LaunchMode.inAppWebView : LaunchMode.externalApplication;
  if (await launchUrl(uri, mode: firstMode)) return true;
  if (firstMode != LaunchMode.externalApplication && await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    return true;
  }
  return launchUrl(uri, mode: LaunchMode.platformDefault);
}

String? _artifactPathFromContent(String content) {
  final patterns = [
    RegExp(r'Saved generated artifact:\s*`([^`]+)`'),
    RegExp(r'Code file:\s*`([^`]+)`'),
    RegExp(r'代码文件:\s*`([^`]+)`'),
  ];
  for (final pattern in patterns) {
    final match = pattern.firstMatch(content);
    final path = match?.group(1)?.trim();
    if (path != null && path.isNotEmpty) return path;
  }
  return null;
}

String? _backtickedValue(String content, String label) {
  final escaped = RegExp.escape(label);
  return RegExp('$escaped:\\s*`([^`]+)`').firstMatch(content)?.group(1)?.trim();
}

class _PublishedArtifactInfo {
  const _PublishedArtifactInfo({
    required this.pagesUrl,
    required this.repositoryUrl,
    required this.artifactPath,
    required this.publishedAt,
    this.readinessSummary,
    this.screenshotPath,
  });

  final String pagesUrl;
  final String repositoryUrl;
  final String artifactPath;
  final DateTime publishedAt;
  final String? readinessSummary;
  final String? screenshotPath;

  String get title {
    final file = artifactPath.split(RegExp(r'[\\/]')).last;
    if (file.isEmpty) return 'Published web page';
    return file;
  }
}

_PublishedArtifactInfo? _pagesDeploymentFromContent(String content, DateTime fallbackTime) {
  if (!content.contains('GitHub Pages deployment completed.')) return null;
  final pagesUrl = _backtickedValue(content, 'Web URL');
  final repositoryUrl = _backtickedValue(content, 'Repository');
  final artifactPath = _backtickedValue(content, 'Code file');
  if (pagesUrl == null || repositoryUrl == null || artifactPath == null) return null;
  final publishedAtRaw = _backtickedValue(content, 'Published at');
  return _PublishedArtifactInfo(
    pagesUrl: pagesUrl,
    repositoryUrl: repositoryUrl,
    artifactPath: artifactPath,
    publishedAt: DateTime.tryParse(publishedAtRaw ?? '') ?? fallbackTime,
    readinessSummary: _backtickedValue(content, 'Pre-publish check'),
    screenshotPath: _backtickedValue(content, 'Screenshot'),
  );
}

bool _isWebArtifactPath(String path) => path.toLowerCase().endsWith('.html') || path.toLowerCase().endsWith('.htm');

bool _looksLikeGeneratedArtifactPayload(String value) {
  final lower = value.toLowerCase();
  return lower.contains('```html') ||
      lower.contains('<!doctype html') ||
      lower.contains('<html') ||
      (value.length > 1800 && (lower.contains('<script') || lower.contains('<style') || lower.contains('function ')));
}

String _assistantNonCodeSummary(String value, {int limit = 420}) {
  var text = value.trim();
  if (text.isEmpty) return '';
  text = text
      .replaceAll(RegExp(r'```(?:html|HTML)\s*[\s\S]*?```'), ' ')
      .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
      .replaceAll(RegExp(r'<!doctype html[\s\S]*?</html>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<html[\s\S]*?</html>', caseSensitive: false), ' ');
  final lower = text.toLowerCase();
  var htmlStart = -1;
  for (final index in [lower.indexOf('<!doctype html'), lower.indexOf('<html')]) {
    if (index >= 0 && (htmlStart == -1 || index < htmlStart)) {
      htmlStart = index;
    }
  }
  if (htmlStart >= 0) {
    text = text.substring(0, htmlStart);
  }
  final lines = text
      .split('\n')
      .map((line) => line.trim())
      .where((line) {
        if (line.isEmpty) return false;
        return !line.startsWith('Agent run completed via provider:') &&
            !line.startsWith('Saved generated artifact:') &&
            !line.startsWith('Phone file path:') &&
            !line.startsWith('Code file:') &&
            !line.startsWith('Web preview:');
      })
      .join(' ');
  return _compact(lines, limit: limit);
}

bool _isAgentResultTurn(String content) {
  final trimmed = content.trimLeft();
  return trimmed.startsWith('Agent run completed via provider:') ||
      trimmed.startsWith('Agent run failed while using') ||
      trimmed.startsWith('Agent run stopped before writing');
}

bool _isFinalResultTurn(String content) {
  final trimmed = content.trimLeft();
  return _isAgentResultTurn(content) ||
      trimmed.startsWith('GitHub Pages deployment completed.') ||
      trimmed.contains('Saved generated artifact:') ||
      trimmed.contains('Code file:');
}

bool _isPublishResultTurn(String content) {
  final trimmed = content.trimLeft();
  return trimmed.startsWith('GitHub Pages deployment completed.') ||
      trimmed.contains('Pages URL:') ||
      trimmed.contains('GitHub Pages URL') ||
      trimmed.contains('发布 GitHub Pages 成功');
}

bool _isCodeResultTurn(String content) {
  final trimmed = content.trimLeft();
  return trimmed.contains('```') ||
      trimmed.contains('<!DOCTYPE html') ||
      trimmed.contains('<html') ||
      trimmed.contains('Saved generated artifact:') ||
      trimmed.contains('Code file:') ||
      trimmed.contains('index.html');
}

bool _isBookmarkedTurn(String content) {
  final lower = content.toLowerCase();
  return lower.contains('#bookmark') || content.contains('书签') || content.contains('重点');
}

bool _promptTargets2048(String prompt) {
  final lower = prompt.toLowerCase();
  return lower.contains('2048') || prompt.contains('二零四八');
}

bool _promptTargetsSnake(String prompt) {
  final lower = prompt.toLowerCase();
  return lower.contains('snake') || prompt.contains('贪吃蛇');
}

bool _promptTargetsDiary(String prompt) {
  final lower = prompt.toLowerCase();
  return lower.contains('diary') || prompt.contains('日记');
}

bool _promptTargetsResearchPreview(String prompt) {
  final lower = prompt.toLowerCase();
  return lower.contains('research') ||
      lower.contains('web search') ||
      lower.contains('3d') ||
      prompt.contains('复杂验收') ||
      prompt.contains('网页搜索') ||
      prompt.contains('搜索资料') ||
      prompt.contains('网页截图') ||
      prompt.contains('预览快照') ||
      prompt.contains('动物森友会');
}

String _agentToolNameForPrompt(String prompt) {
  final lower = prompt.toLowerCase();
  if (_promptTargetsResearchPreview(prompt)) return 'mobile_coding.research_web_preview';
  if (_promptTargetsSnake(prompt)) return 'mobile_coding.generate_snake_preview';
  if (_promptTargets2048(prompt)) return 'mobile_coding.generate_2048_preview';
  if (_promptTargetsDiary(prompt)) return 'mobile_coding.build_diary_demo';
  if (lower.contains('termux') || lower.contains('terminal') || lower.contains('shell')) {
    return 'mobile_tools.termux_probe';
  }
  if (lower.contains('github') || lower.contains('repo')) {
    return 'github.connectivity_test';
  }
  if (lower.contains('game') || lower.contains('web') || lower.contains('html') || lower.contains('preview')) {
    return 'mobile_coding.generate_web_preview';
  }
  return 'mobile_tools.core_probe';
}

String _agentToolSelectionReason(String tool, String prompt) {
  if (tool == 'mobile_coding.generate_snake_preview') {
    return 'The prompt asks for a snake game, so MobileCode selects the local web-game generator and expects one self-contained HTML file.';
  }
  if (tool == 'mobile_coding.generate_2048_preview') {
    return 'The prompt asks for a 2048 game, so MobileCode selects the local web-game generator and expects one self-contained HTML file.';
  }
  if (tool == 'mobile_coding.generate_web_preview') {
    return 'The prompt targets a web/html/preview workflow, so MobileCode selects the local WebView preview artifact path.';
  }
  if (tool == 'mobile_coding.research_web_preview') {
    return 'The prompt asks for a researched WebView demo, so MobileCode exposes safe provider-native web/file/preview tools and lets the model choose the smallest useful steps.';
  }
  if (tool == 'mobile_coding.build_diary_demo') {
    return 'The prompt asks for an app feature plan, so MobileCode keeps the result as a generated Markdown implementation note.';
  }
  if (tool == 'mobile_tools.termux_probe') {
    return 'The prompt mentions shell/Termux/runtime, so MobileCode selects a runtime diagnostics tool instead of pretending full shell execution happened.';
  }
  if (tool == 'github.connectivity_test') {
    return 'The prompt mentions GitHub/repo checks, so MobileCode selects the GitHub connectivity tester path.';
  }
  return 'No specialized coding target was detected, so MobileCode selects the core mobile tool probe.';
}

String _agentToolExpectedOutput(String tool) {
  if (tool.startsWith('mobile_coding.generate_')) {
    return 'Provider response -> complete HTML code -> app writes index.html -> WebView preview and browser-open actions become available.';
  }
  if (tool == 'mobile_coding.research_web_preview') {
    return 'Provider-native Agent Loop -> model chooses safe web/file/preview tools -> ActionRunner executes -> evidence observations return to the model -> final report.';
  }
  if (tool == 'mobile_coding.build_diary_demo') {
    return 'Provider response -> app writes agent_response.md so the user can inspect or copy the implementation plan.';
  }
  if (tool == 'mobile_tools.termux_probe') {
    return 'Runtime status explanation only. It should not claim that a shell command ran unless the runtime provider reports it.';
  }
  if (tool == 'github.connectivity_test') {
    return 'Provider-guided connectivity checklist and failure explanation for token/repository access.';
  }
  return 'Provider response is reported in chat without writing a project artifact.';
}

String _agentLocalToolChainFor(String tool) {
  if (tool == 'mobile_coding.generate_snake_preview' ||
      tool == 'mobile_coding.generate_2048_preview' ||
      tool == 'mobile_coding.generate_web_preview') {
    return '1. Parse complete HTML from provider output\n'
        '2. write_file: save index.html inside app documents with temp-file rename\n'
        '3. read_file: verify the saved artifact path/content\n'
        '4. preview_webview: expose the in-app WebView preview action';
  }
  if (tool == 'mobile_coding.research_web_preview') {
    return 'Available safe tools: list_files, find_files, grep_files, web_search, fetch_url, write_file, read_file, move_file, apply_patch, preview_html, preview_snapshot, report_result.\n'
        'The model may choose the smallest useful next step; MobileCode validates, executes, records evidence, and returns observations.';
  }
  if (tool == 'mobile_coding.build_diary_demo') {
    return '1. Validate provider output is not empty\n'
        '2. write_file: save agent_response.md inside app documents\n'
        '3. Show copy/open actions for inspection';
  }
  if (tool == 'mobile_tools.termux_probe') {
    return 'No shell claim is made from provider text alone. Runtime checks must come from RuntimeProvider capability/status results.';
  }
  if (tool == 'github.connectivity_test') {
    return 'GitHub checks must use the GitHub test surface/API result, not only the model explanation.';
  }
  return 'No local write tool is expected for this prompt. The final answer stays as chat text.';
}

Map<String, String> _agentToolCallDetails(String tool, String prompt) {
  final writesFile = tool.startsWith('mobile_coding.');
  final isWeb = tool == 'mobile_coding.generate_snake_preview' ||
      tool == 'mobile_coding.generate_2048_preview' ||
      tool == 'mobile_coding.generate_web_preview' ||
      tool == 'mobile_coding.research_web_preview';
  return {
    'Tool': tool,
    'Why selected': _agentToolSelectionReason(tool, prompt),
    'Input': _compact(prompt, limit: 420),
    'Expected output': _agentToolExpectedOutput(tool),
    'Write target': writesFile
        ? (isWeb ? 'App documents/mobilecode_projects/<tool_slug>/index.html' : 'App documents/mobilecode_projects/<tool_slug>/agent_response.md')
        : 'No file write for this tool selection step.',
    'Safety boundary': 'No arbitrary shell is executed during tool selection. File writes stay inside MobileCode app documents.',
  };
}

List<_AgentTraceStep> _agentRunTraceTemplate(String prompt) {
  final tool = _agentToolNameForPrompt(prompt);
  return [
    _AgentTraceStep(
      title: 'Parse instruction',
      detail: 'Read the user request and decide whether this is chat, coding, preview, GitHub, or device tooling.',
      icon: Icons.manage_search_outlined,
      avatarAsset: 'assets/role_avatars/claude-pet-animated-magic.svg',
      traceAction: MobileCodeAction.traceParseInstruction,
      details: {
        'Input': _compact(prompt, limit: 420),
        'Decision rule': 'Classify the prompt before any provider call or file write.',
      },
    ),
    _AgentTraceStep(
      title: 'Select tool',
      detail: '$tool · tap for call details',
      icon: Icons.psychology_alt_outlined,
      avatarAsset: 'assets/role_avatars/claude-pet-animated-coder.svg',
      toolName: tool,
      traceAction: MobileCodeAction.traceSelectTool,
      details: _agentToolCallDetails(tool, prompt),
    ),
    _AgentTraceStep(
      title: 'Call model provider',
      detail:
          'Send the prompt and chat context to the configured provider, then continue into visible local tool actions.',
      icon: Icons.cloud_sync_outlined,
      avatarAsset: 'assets/role_avatars/claude-girl-dancer.svg',
      traceAction: MobileCodeAction.traceCallProvider,
      details: {
        'Provider call': 'Uses the configured Base URL, model, API flavor, and current chat context.',
        'Streaming': 'Tokens are streamed into this trace while the provider responds.',
        'Local tool chain': _agentLocalToolChainFor(tool),
        'Transparency rule':
            'Provider text is not treated as completion by itself. MobileCode must show the selected local tool, file write target, saved path, and preview action before reporting done.',
        'Cancel behavior': 'Pause closes the current provider request and prevents additional file writes.',
      },
    ),
    _AgentTraceStep(
      title: 'Write generated artifact',
      detail: 'Persist model-generated code only after the provider returns real output.',
      icon: Icons.account_tree_outlined,
      avatarAsset: 'assets/role_avatars/claude-pet-animated-rocket.svg',
      traceAction: MobileCodeAction.traceWriteArtifact,
      details: {
        'Write rule': 'Generated files are written only after provider text is received and validated.',
        'Web validation': 'HTML tools require a complete HTML document before index.html is replaced.',
        'Atomicity': 'Web artifacts use a temp file followed by rename to avoid partial index.html output.',
      },
    ),
    _AgentTraceStep(
      title: 'Report in chat',
      detail: 'Keep the process, generated content, paths, and failure state in this conversation.',
      icon: Icons.play_arrow_outlined,
      avatarAsset: 'assets/role_avatars/claude-pet-animated-wave.svg',
      traceAction: MobileCodeAction.traceReportChat,
      details: {
        'Chat report': 'The final assistant message includes the selected tool, saved path, and generated content.',
        'Artifact actions': 'Generated artifacts can be opened as code, previewed in WebView, copied, or opened in a browser when HTML.',
      },
    ),
  ];
}

Future<bool?> _isAndroidPackageInstalled(String packageName) async {
  try {
    return await _systemToolsChannel.invokeMethod<bool>('isPackageInstalled', {
      'packageName': packageName,
    });
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}

Future<bool> _launchAndroidPackage(String packageName) async {
  try {
    return await _systemToolsChannel.invokeMethod<bool>('launchPackage', {
          'packageName': packageName,
        }) ??
        false;
  } on MissingPluginException {
    return false;
  } on PlatformException {
    return false;
  }
}

Future<_RootProbeResult?> _probeRootAvailability() async {
  try {
    final result = await _systemToolsChannel.invokeMethod<Map<dynamic, dynamic>>('rootProbe');
    if (result == null) return null;
    return _RootProbeResult.fromMap(result);
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}

Future<bool?> _startMobileCodeHelperService() async {
  try {
    return await _systemToolsChannel.invokeMethod<bool>('startHelperService');
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return false;
  }
}

String _localTool2048Html() {
  return r'''<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
  <title>MobileCode Agent 2048</title>
  <style>
    :root { color-scheme: dark; --bg:#05070c; --panel:#101522; --cell:#1a2133; --line:#293049; --text:#f0f3fa; --muted:#9ea6bd; --mint:#7af2c7; --amber:#ffc66b; --violet:#8b5cf6; --cyan:#62d9ff; --rose:#ff6e87; }
    * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
    body { margin: 0; min-height: 100svh; display: grid; place-items: center; background: var(--bg); color: var(--text); font-family: system-ui, -apple-system, "Segoe UI", sans-serif; padding: 18px; touch-action: none; }
    .app { width: min(100%, 430px); }
    header { display: flex; align-items: end; justify-content: space-between; gap: 12px; margin-bottom: 18px; }
    h1 { margin: 0; font-size: 50px; line-height: .95; letter-spacing: 0; }
    .sub { color: var(--muted); margin: 6px 0 0; font-size: 13px; }
    .scores { display: flex; gap: 8px; }
    .score { background: var(--panel); border: 1px solid var(--line); border-radius: 8px; padding: 9px 12px; min-width: 76px; text-align: center; }
    .score span { display:block; color: var(--muted); font-size: 11px; font-weight: 800; text-transform: uppercase; }
    .score strong { font-size: 20px; }
    .board { display:grid; grid-template-columns: repeat(4, 1fr); gap: 10px; width: 100%; aspect-ratio: 1; background: var(--panel); border: 1px solid var(--line); border-radius: 8px; padding: 10px; box-shadow: 0 30px 80px rgba(0,0,0,.35); }
    .tile { display:grid; place-items:center; border-radius: 8px; background: var(--cell); color: var(--text); font-weight: 900; font-size: clamp(22px, 8vw, 42px); transition: transform .1s ease, background .15s ease; user-select:none; }
    .tile.new { animation: pop .16s ease both; }
    @keyframes pop { from { transform: scale(.82); } to { transform: scale(1); } }
    .v2 { background:#1e2d3d; color:var(--mint); } .v4 { background:#223940; color:#9ff7d8; } .v8 { background:#4f3a25; color:var(--amber); } .v16 { background:#5b2d31; color:#ffb1bf; } .v32 { background:#522d64; color:#d4b9ff; } .v64 { background:#253b67; color:#b9d7ff; }
    .v128,.v256,.v512 { background: linear-gradient(135deg, var(--violet), var(--cyan)); color:#05070c; } .v1024,.v2048 { background: linear-gradient(135deg, var(--mint), var(--amber)); color:#05070c; }
    .controls { display:flex; gap:10px; margin-top:16px; }
    button { flex:1; border:1px solid var(--line); border-radius:8px; padding:14px 12px; background:var(--panel); color:var(--text); font-weight:900; }
    button.primary { background:var(--violet); border-color: transparent; }
    .hint { margin-top:14px; color:var(--muted); text-align:center; font-size:13px; line-height:1.45; }
    .status { color: var(--rose); font-weight: 900; }
  </style>
</head>
<body>
  <main class="app">
    <header>
      <div>
        <h1>2048</h1>
        <p class="sub">Generated locally by MobileCode Agent</p>
      </div>
      <div class="scores">
        <div class="score"><span>score</span><strong id="score">0</strong></div>
        <div class="score"><span>best</span><strong id="best">0</strong></div>
      </div>
    </header>
    <section class="board" id="board" aria-label="2048 board"></section>
    <div class="controls">
      <button class="primary" id="new">New game</button>
      <button id="undo">Undo</button>
    </div>
    <p class="hint">Swipe on the board. Merge tiles until <span class="status">2048</span>.</p>
  </main>
  <script>
    const board = document.querySelector("#board");
    const scoreEl = document.querySelector("#score");
    const bestEl = document.querySelector("#best");
    const size = 4;
    let grid = [];
    let previous = null;
    let score = 0;
    let best = Number(localStorage.getItem("mobilecode-2048-best") || 0);
    bestEl.textContent = best;

    function emptyGrid() { return Array.from({ length: size }, () => Array(size).fill(0)); }
    function clone(value) { return value.map(row => row.slice()); }
    function emptyCells() {
      const cells = [];
      for (let r = 0; r < size; r++) for (let c = 0; c < size; c++) if (!grid[r][c]) cells.push([r, c]);
      return cells;
    }
    function addTile() {
      const cells = emptyCells();
      if (!cells.length) return;
      const [r, c] = cells[Math.floor(Math.random() * cells.length)];
      grid[r][c] = Math.random() < .9 ? 2 : 4;
    }
    function render() {
      board.innerHTML = "";
      for (let r = 0; r < size; r++) {
        for (let c = 0; c < size; c++) {
          const value = grid[r][c];
          const tile = document.createElement("div");
          tile.className = "tile" + (value ? " v" + value : "");
          tile.textContent = value || "";
          board.appendChild(tile);
        }
      }
      scoreEl.textContent = score;
      best = Math.max(best, score);
      bestEl.textContent = best;
      localStorage.setItem("mobilecode-2048-best", best);
    }
    function compact(row) {
      const values = row.filter(Boolean);
      for (let i = 0; i < values.length - 1; i++) {
        if (values[i] === values[i + 1]) {
          values[i] *= 2;
          score += values[i];
          values.splice(i + 1, 1);
        }
      }
      while (values.length < size) values.push(0);
      return values;
    }
    function rotateRight(matrix) {
      return matrix[0].map((_, i) => matrix.map(row => row[i]).reverse());
    }
    function rotateLeft(matrix) {
      return matrix[0].map((_, i) => matrix.map(row => row[size - 1 - i]));
    }
    function move(direction) {
      previous = { grid: clone(grid), score };
      const before = JSON.stringify(grid);
      if (direction === "left") grid = grid.map(compact);
      if (direction === "right") grid = grid.map(row => compact(row.slice().reverse()).reverse());
      if (direction === "up") { grid = rotateLeft(grid); grid = grid.map(compact); grid = rotateRight(grid); }
      if (direction === "down") { grid = rotateLeft(grid); grid = grid.map(row => compact(row.slice().reverse()).reverse()); grid = rotateRight(grid); }
      if (JSON.stringify(grid) !== before) addTile();
      render();
    }
    function reset() { grid = emptyGrid(); score = 0; previous = null; addTile(); addTile(); render(); }
    document.querySelector("#new").onclick = reset;
    document.querySelector("#undo").onclick = () => { if (previous) { grid = previous.grid; score = previous.score; previous = null; render(); } };
    window.addEventListener("keydown", event => {
      const map = { ArrowLeft: "left", ArrowRight: "right", ArrowUp: "up", ArrowDown: "down" };
      if (map[event.key]) move(map[event.key]);
    });
    let startX = 0, startY = 0;
    board.addEventListener("touchstart", event => { startX = event.touches[0].clientX; startY = event.touches[0].clientY; }, { passive: true });
    board.addEventListener("touchend", event => {
      const dx = event.changedTouches[0].clientX - startX;
      const dy = event.changedTouches[0].clientY - startY;
      if (Math.max(Math.abs(dx), Math.abs(dy)) < 24) return;
      move(Math.abs(dx) > Math.abs(dy) ? (dx > 0 ? "right" : "left") : (dy > 0 ? "down" : "up"));
    }, { passive: true });
    reset();
  </script>
</body>
</html>''';
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.brandTheme = 'codexBlue',
    this.onBrandThemeChanged,
  });

  final String brandTheme;
  final ValueChanged<String>? onBrandThemeChanged;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _baseUrlKey = 'mobilecode.baseUrl';
  static const _apiKeyKey = 'mobilecode.apiKey';
  static const _modelKey = 'mobilecode.model';
  static const _providerModeKey = 'mobilecode.providerMode';
  static const _managedProviderPresetKey = 'mobilecode.managedProviderPreset';
  static const _brandThemeKey = 'mobilecode.brandTheme';
  static const _browserOpenModeKey = 'mobilecode.browserOpenMode';

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _chatPanelKey = GlobalKey<_ChatPanelState>();
  final _baseUrlController = TextEditingController(text: _defaultBaseUrl);
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController(text: _defaultModel);

  _HealthState _healthState = _HealthState.unknown;
  String _healthMessage = 'Not checked';
  bool _saving = false;
  _HomeTab _tab = _HomeTab.control;
  int _selectedLayerIndex = 0;
  bool _showCapabilityMap = false;
  bool _runtimeChecking = false;
  bool _customProviderOverride = false;
  _ProviderPreset _managedProviderPreset = _ProviderPreset.mimo;
  String _brandTheme = 'codexBlue';
  String _browserOpenMode = _browserOpenModeSystem;
  bool? _termuxInstalled;
  bool? _termuxApiInstalled;
  bool? _rootAvailable;
  String _runtimeMessage = 'Checking runtime providers...';
  List<RuntimeHealth> _runtimeHealth = const [];
  RuntimeCapabilities _runtimeCapabilities = RuntimeCapabilities.none;
  List<_ChatSession> _drawerSessions = const [];
  String? _drawerActiveSessionId;

  late final RuntimeManager _runtimeManager = RuntimeManager.withExternalTermux(TermuxService());

  final List<_ActivityLog> _activity = [
    _ActivityLog(
      title: 'Frontend map loaded',
      detail: 'AI, Agents, Code, Remote, Guard, Analytics, Tools, Performance, Team',
      icon: Icons.dashboard_customize_outlined,
      color: _mint,
      time: DateTime.now(),
    ),
  ];
  final List<_DraftFile> _drafts = [];
  final List<_SnippetDraft> _snippets = [];

  List<_CapabilityLayer> get _layers => _capabilityLayers;

  int get _safeLayerIndex {
    if (_selectedLayerIndex < 0) return 0;
    if (_selectedLayerIndex >= _layers.length) return _layers.length - 1;
    return _selectedLayerIndex;
  }

  _CapabilityLayer get _activeLayer => _layers[_safeLayerIndex];

  List<_ProviderPreset> get _managedProviderPresets => _availableManagedProviderPresets();

  bool get _managedProviderAvailable => _managedProviderPresets.isNotEmpty;

  _ProviderPreset get _activeManagedProviderPreset {
    if (_managedProviderPresetAvailable(_managedProviderPreset)) {
      return _managedProviderPreset;
    }
    return _firstManagedProviderPreset();
  }

  bool get _managedProviderActive => _managedProviderAvailable && !_customProviderOverride && _managedProviderPresetAvailable(_activeManagedProviderPreset);

  String get _effectiveBaseUrl => _managedProviderActive ? _managedProviderBaseUrl(_activeManagedProviderPreset) : _baseUrlController.text.trim();

  String get _effectiveApiKey => _managedProviderActive ? _managedProviderApiKey(_activeManagedProviderPreset) : _apiKeyController.text.trim();

  String get _effectiveModel => _managedProviderActive ? _managedProviderModel(_activeManagedProviderPreset) : _modelController.text.trim();

  _ApiFlavor get _flavor {
    return _detectApiFlavor(_effectiveBaseUrl, _effectiveModel);
  }

  RuntimeHealth? get _bestRuntimeHealth {
    final active = _runtimeManager.activeHealth;
    if (active != null) return active;
    for (final health in _runtimeHealth) {
      if (health.ready) return health;
    }
    return _runtimeHealth.isNotEmpty ? _runtimeHealth.first : null;
  }

  String get _activeRuntimeName => _bestRuntimeHealth?.name ?? 'WebView Only';

  bool get _runtimeReady => _bestRuntimeHealth?.ready == true;

  String get _runtimeDrawerLabel {
    final runtime = _bestRuntimeHealth;
    final capabilityLabel = _runtimeCapabilityLabel(_runtimeCapabilities);
    final fallback = <String>[
      if (_termuxInstalled == true) _termuxApiInstalled == true ? 'External Termux API fallback' : 'External Termux fallback',
      if (_rootAvailable == true) 'root keepalive',
    ];
    if (runtime == null) {
      return fallback.isEmpty ? 'Runtime discovery pending' : fallback.join(' · ');
    }
    return fallback.isEmpty ? '${runtime.name} · $capabilityLabel' : '${runtime.name} · $capabilityLabel · ${fallback.join(' · ')}';
  }

  @override
  void initState() {
    super.initState();
    _brandTheme = _normalizeBrandTheme(widget.brandTheme);
    _loadConfig();
    unawaited(_checkRuntime(silent: true));
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.brandTheme != widget.brandTheme) {
      _brandTheme = _normalizeBrandTheme(widget.brandTheme);
    }
  }

  @override
  void dispose() {
    unawaited(_runtimeManager.dispose());
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        final savedManagedPreset = _providerPresetFromName(prefs.getString(_managedProviderPresetKey));
        _managedProviderPreset = _managedProviderPresetAvailable(savedManagedPreset) ? savedManagedPreset : _firstManagedProviderPreset();
        _customProviderOverride = prefs.getString(_providerModeKey) == 'custom' || !_managedProviderPresetAvailable(_managedProviderPreset);
        _brandTheme = _normalizeBrandTheme(
          prefs.getString(_brandThemeKey) ?? widget.brandTheme,
        );
        _browserOpenMode = _normalizeBrowserOpenMode(prefs.getString(_browserOpenModeKey));
        if (_managedProviderActive) {
          _baseUrlController.text = '';
          _apiKeyController.text = '';
          _modelController.text = '';
        } else {
          _baseUrlController.text = _savedOrDefault(prefs.getString(_baseUrlKey), _defaultBaseUrl);
          _apiKeyController.text = prefs.getString(_apiKeyKey) ?? '';
          _modelController.text = _savedOrDefault(prefs.getString(_modelKey), _defaultModel);
        }
      });
    } on Object catch (error) {
      _addLog('Config load failed', _compact(error.toString(), limit: 120), Icons.error_outline, _rose);
    }
  }

  void _applyDefaultProvider() {
    _applyProviderPreset(_ProviderPreset.mimo);
  }

  Future<void> _setProviderMode({required bool useCustom}) async {
    if (!useCustom && !_managedProviderAvailable) {
      _showMessage('Managed provider is not available in this build');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final nextManagedPreset = _managedProviderPresetAvailable(_managedProviderPreset) ? _managedProviderPreset : _firstManagedProviderPreset();
    await prefs.setString(_providerModeKey, useCustom ? 'custom' : 'managed');
    if (!useCustom) {
      await prefs.setString(_managedProviderPresetKey, nextManagedPreset.name);
    }
    if (!mounted) return;
    setState(() {
      _customProviderOverride = useCustom;
      if (!useCustom) _managedProviderPreset = nextManagedPreset;
      if (useCustom) {
        _baseUrlController.text = _savedOrDefault(prefs.getString(_baseUrlKey), _defaultBaseUrl);
        _apiKeyController.text = prefs.getString(_apiKeyKey) ?? '';
        _modelController.text = _savedOrDefault(prefs.getString(_modelKey), _defaultModel);
      } else {
        _baseUrlController.text = '';
        _apiKeyController.text = '';
        _modelController.text = '';
      }
    });
    _addLog(
      useCustom ? 'Custom provider enabled' : 'Managed provider enabled',
      useCustom ? 'Base URL, API key, and model fields are editable.' : '${_providerPresetLabel(_managedProviderPreset)} bundled credentials are active and hidden in the UI.',
      Icons.tune_outlined,
      useCustom ? _cyan : _mint,
    );
  }

  Future<void> _selectProviderFromComposer(_ProviderPreset preset) async {
    final prefs = await SharedPreferences.getInstance();
    if (preset != _ProviderPreset.custom && _managedProviderPresetAvailable(preset)) {
      await prefs.setString(_providerModeKey, 'managed');
      await prefs.setString(_managedProviderPresetKey, preset.name);
      if (!mounted) return;
      setState(() {
        _customProviderOverride = false;
        _managedProviderPreset = preset;
        _baseUrlController.clear();
        _apiKeyController.clear();
        _modelController.clear();
      });
      _addLog(
        '${_providerPresetLabel(preset)} model selected',
        'Built-in provider credentials stay hidden. Chat and Agent now use ${_managedProviderModel(preset)}.',
        Icons.tune_outlined,
        preset == _ProviderPreset.deepSeek ? _violet : _mint,
      );
      return;
    }

    final presetBaseUrl = _providerPresetBaseUrl(preset);
    final presetModel = _providerPresetModel(preset);
    await prefs.setString(_providerModeKey, 'custom');
    if (presetBaseUrl.isNotEmpty) await prefs.setString(_baseUrlKey, presetBaseUrl);
    if (presetModel.isNotEmpty) await prefs.setString(_modelKey, presetModel);
    if (!mounted) return;
    setState(() {
      _customProviderOverride = true;
      if (presetBaseUrl.isNotEmpty) _baseUrlController.text = presetBaseUrl;
      if (presetModel.isNotEmpty) _modelController.text = presetModel;
      _apiKeyController.text = prefs.getString(_apiKeyKey) ?? '';
    });
    _addLog(
      '${_providerPresetLabel(preset)} custom profile selected',
      preset == _ProviderPreset.custom
          ? 'Custom provider keeps the saved Base URL, model, and local key.'
          : 'No bundled key is active for this profile; paste a key in Models & Provider if needed.',
      Icons.tune_outlined,
      _cyan,
    );
  }

  Future<void> _setBrandTheme(String value) async {
    final normalized = _normalizeBrandTheme(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_brandThemeKey, normalized);
    if (!mounted) return;
    setState(() => _brandTheme = normalized);
    widget.onBrandThemeChanged?.call(normalized);
    _addLog(
      normalized == 'claudeYellow' ? 'Claude Yellow theme enabled' : 'Codex Blue theme enabled',
      'Theme preference saved on this device.',
      Icons.palette_outlined,
      normalized == 'claudeYellow' ? _amber : _blue,
    );
  }

  Future<void> _setBrowserOpenMode(String value) async {
    final normalized = _normalizeBrowserOpenMode(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_browserOpenModeKey, normalized);
    if (!mounted) return;
    setState(() => _browserOpenMode = normalized);
    _addLog(
      'Browser open mode saved',
      _browserOpenModeLabel(normalized),
      normalized == _browserOpenModeInApp ? Icons.web_asset_outlined : Icons.open_in_browser_outlined,
      normalized == _browserOpenModeInApp ? _violet : _amber,
    );
  }

  void _applyProviderPreset(_ProviderPreset preset) {
    if (_managedProviderActive) {
      _customProviderOverride = true;
      unawaited(SharedPreferences.getInstance().then((prefs) => prefs.setString(_providerModeKey, 'custom')));
    }
    setState(() {
      final presetBaseUrl = _providerPresetBaseUrl(preset);
      final presetModel = _providerPresetModel(preset);
      if (presetBaseUrl.isNotEmpty) {
        _baseUrlController.text = presetBaseUrl;
      }
      if (presetModel.isNotEmpty) {
        _modelController.text = presetModel;
      }
    });
    final label = _providerPresetLabel(preset);
    _addLog(
      '$label provider selected',
      preset == _ProviderPreset.custom
          ? 'Custom mode keeps your current Base URL/model so you can edit them directly.'
          : 'Base URL and model filled. API key stays private.',
      Icons.tune_outlined,
      preset == _ProviderPreset.custom ? _cyan : _mint,
    );
  }

  Future<void> _saveConfig() async {
    if (_managedProviderActive) {
      _showMessage('Switch to Custom provider before saving your own Base URL');
      return;
    }
    setState(() => _saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_providerModeKey, 'custom');
      await prefs.setString(_baseUrlKey, _baseUrlController.text.trim());
      await prefs.setString(_apiKeyKey, _apiKeyController.text.trim());
      await prefs.setString(_modelKey, _modelController.text.trim());
      if (!mounted) return;
      setState(() => _customProviderOverride = true);
      _addLog(
        'API profile saved',
        '${_flavorLabel(_flavor)} - ${_effectiveModel.isEmpty ? 'default model' : _effectiveModel}',
        Icons.key_outlined,
        _mint,
      );
      _showMessage('API config saved');
    } on Object catch (error) {
      if (!mounted) return;
      _addLog('API save failed', _compact(error.toString(), limit: 140), Icons.error_outline, _rose);
      _showMessage('API config save failed');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _checkHealth() async {
    final baseUrl = _effectiveBaseUrl;
    if (baseUrl.isEmpty) {
      _showMessage('Set Base URL first');
      return;
    }

    final flavor = _flavor;
    try {
      _parseBaseUrl(baseUrl);
    } catch (_) {
      _showMessage('Base URL is not valid');
      return;
    }

    setState(() {
      _healthState = _HealthState.checking;
      _healthMessage = 'Checking ${_chatEndpointLabel(baseUrl, flavor)}';
    });

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final apiKey = _effectiveApiKey;
      final model = _effectiveModel;
      late final _ProbeResult result;

      if (flavor == _ApiFlavor.anthropic) {
        result = await _probeAnthropic(client, baseUrl, apiKey, model);
      } else {
        _ProbeResult? lastResult;
        for (final probe in _openAiHealthUris(baseUrl)) {
          final probeResult = await _probeGet(client, probe, apiKey);
          lastResult = probeResult;
          if (probeResult.isHealthy) break;
        }
        result = lastResult!;
      }

      if (!mounted) return;
      setState(() {
        _healthState = result.isHealthy ? _HealthState.healthy : _HealthState.failed;
        _healthMessage = result.message;
      });
      _addLog(
        result.isHealthy ? 'Provider healthy' : 'Provider unhealthy',
        result.message,
        result.isHealthy ? Icons.check_circle_outline : Icons.error_outline,
        result.isHealthy ? _mint : _rose,
      );
    } on SocketException catch (error) {
      if (!mounted) return;
      final message = _friendlySocketError(error);
      setState(() {
        _healthState = _HealthState.failed;
        _healthMessage = message;
      });
      _addLog('Health check failed', _compact(message, limit: 140), Icons.error_outline, _rose);
    } on Object catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst('Exception: ', '');
      setState(() {
        _healthState = _HealthState.failed;
        _healthMessage = message;
      });
      _addLog('Health check failed', _compact(message, limit: 140), Icons.error_outline, _rose);
    } finally {
      client.close(force: true);
    }
  }

  Future<_ProbeResult> _probeGet(HttpClient client, Uri uri, String apiKey) async {
    final started = DateTime.now();
    final request = await client.getUrl(uri).timeout(const Duration(seconds: 8));
    if (apiKey.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
    }
    final response = await request.close().timeout(const Duration(seconds: 12));
    await response.drain();
    final ms = DateTime.now().difference(started).inMilliseconds;
    return _ProbeResult(
      uri: uri,
      statusCode: response.statusCode,
      latencyMs: ms,
      message: '${uri.path} HTTP ${response.statusCode} - ${ms}ms',
    );
  }

  Future<_ProbeResult> _probeAnthropic(
    HttpClient client,
    String baseUrl,
    String apiKey,
    String model,
  ) async {
    final uri = _anthropicMessagesUri(baseUrl);
    final started = DateTime.now();
    final request = await client.postUrl(uri).timeout(const Duration(seconds: 8));
    request.headers.contentType = ContentType.json;
    request.headers.set('anthropic-version', '2023-06-01');
    if (apiKey.isNotEmpty) {
      request.headers.set('x-api-key', apiKey);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
    }
    request.write(jsonEncode({
      'model': model.isEmpty ? 'claude-3-5-haiku-latest' : model,
      'max_tokens': 1,
      'messages': [
        {'role': 'user', 'content': 'ping'},
      ],
    }));

    final response = await request.close().timeout(const Duration(seconds: 30));
    final body = await utf8.decodeStream(response);
    final ms = DateTime.now().difference(started).inMilliseconds;
    return _ProbeResult(
      uri: uri,
      statusCode: response.statusCode,
      latencyMs: ms,
      message: response.statusCode >= 200 && response.statusCode < 300
          ? '${uri.path} HTTP ${response.statusCode} - ${ms}ms'
          : '${uri.path} HTTP ${response.statusCode} - ${_compact(body, limit: 140)}',
    );
  }

  Future<String> _polishRoleIntent(String intent) async {
    final baseUrl = _effectiveBaseUrl;
    final apiKey = _effectiveApiKey;
    final model = _effectiveModel;
    if (baseUrl.isEmpty) {
      throw Exception('Provider is not configured: Base URL is empty.');
    }
    if (apiKey.isEmpty) {
      throw Exception('Provider is not configured: API key is empty.');
    }

    final flavor = _detectApiFlavor(baseUrl, model);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    final usageStarted = DateTime.now();
    try {
      final request = await client
          .postUrl(flavor == _ApiFlavor.anthropic ? _anthropicMessagesUri(baseUrl) : _openAiChatUri(baseUrl))
          .timeout(const Duration(seconds: 12));
      request.headers.contentType = ContentType.json;
      if (flavor == _ApiFlavor.anthropic) {
        request.headers.set('anthropic-version', '2023-06-01');
        request.headers.set('x-api-key', apiKey);
      }
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      request.write(jsonEncode(_rolePolishRequestBody(flavor, model, intent)));

      final response = await request.close().timeout(const Duration(seconds: 90));
      final body = await utf8.decodeStream(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('AI role polish HTTP ${response.statusCode}: ${_compact(body, limit: 220)}');
      }
      final answer = _extractProviderText(body);
      if (answer.trim().isEmpty) {
        throw Exception('AI role polish returned an empty response.');
      }
      await TokenUsageService.instance.recordCompleted(
        provider: _flavorLabel(flavor),
        model: model,
        endpoint: 'role_polish',
        durationMs: DateTime.now().difference(usageStarted).inMilliseconds,
        success: true,
        usage: _providerUsageFromBody(flavor, body),
        inputChars: rolePolishSystemPrompt.length + intent.length,
        outputChars: answer.length,
      );
      return answer;
    } on SocketException catch (error) {
      await TokenUsageService.instance.recordCompleted(
        provider: _flavorLabel(flavor),
        model: model,
        endpoint: 'role_polish',
        durationMs: DateTime.now().difference(usageStarted).inMilliseconds,
        success: false,
        inputChars: rolePolishSystemPrompt.length + intent.length,
        outputChars: 0,
      );
      throw Exception('AI role polish network error: ${_friendlySocketError(error)}');
    } on TimeoutException {
      await TokenUsageService.instance.recordCompleted(
        provider: _flavorLabel(flavor),
        model: model,
        endpoint: 'role_polish',
        durationMs: DateTime.now().difference(usageStarted).inMilliseconds,
        success: false,
        inputChars: rolePolishSystemPrompt.length + intent.length,
        outputChars: 0,
      );
      throw TimeoutException('AI role polish timed out while waiting for the provider.');
    } finally {
      client.close(force: true);
    }
  }

  Map<String, dynamic> _rolePolishRequestBody(_ApiFlavor flavor, String model, String intent) {
    final resolvedModel = model.isEmpty
        ? (flavor == _ApiFlavor.anthropic ? _defaultModel : 'gpt-4o-mini')
        : model;
    if (flavor == _ApiFlavor.anthropic) {
      return {
        'model': resolvedModel,
        'system': rolePolishSystemPrompt,
        'max_tokens': 1200,
        'temperature': 0.2,
        'messages': [
          {'role': 'user', 'content': intent},
        ],
      };
    }
    return {
      'model': resolvedModel,
      'temperature': 0.2,
      'messages': [
        {'role': 'system', 'content': rolePolishSystemPrompt},
        {'role': 'user', 'content': intent},
      ],
    };
  }

  String _extractProviderText(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final choices = decoded['choices'];
        if (choices is List && choices.isNotEmpty) {
          final first = choices.first;
          if (first is Map<String, dynamic>) {
            final message = first['message'];
            if (message is Map<String, dynamic>) {
              final content = message['content'];
              if (content is String && content.trim().isNotEmpty) return content.trim();
            }
            final text = first['text'];
            if (text is String && text.trim().isNotEmpty) return text.trim();
          }
        }
        final content = decoded['content'];
        if (content is List && content.isNotEmpty) {
          final parts = <String>[];
          for (final item in content) {
            if (item is Map<String, dynamic>) {
              final text = item['text'];
              if (text is String && text.trim().isNotEmpty) parts.add(text.trim());
            }
          }
          if (parts.isNotEmpty) return parts.join('\n\n');
        }
      }
    } catch (_) {
      // Fall back to the compact raw body below.
    }
    return _compact(body, limit: 1600);
  }

  List<Uri> _openAiHealthUris(String baseUrl) {
    final normalized = _normalizedBaseUrl(baseUrl);
    final probes = [
      Uri.parse('$normalized/health'),
      Uri.parse('$normalized/models'),
    ];
    if (!normalized.endsWith('/v1')) {
      probes.add(Uri.parse('$normalized/v1/models'));
    }
    return probes;
  }

  Future<void> _checkRuntime({bool silent = false}) async {
    if (_runtimeChecking) return;
    setState(() {
      _runtimeChecking = true;
      if (!silent) _runtimeMessage = 'Checking MobileCode runtime providers...';
    });
    try {
      if (!silent) {
        await _startMobileCodeHelperService();
      }
      await _runtimeManager.initialize();
      final runtimeHealth = await _runtimeManager.refresh();
      final runtimeCapabilities = await _runtimeManager.capabilities();
      final activeRuntime = _runtimeManager.activeHealth;
      final termux = await _isAndroidPackageInstalled('com.termux');
      final termuxApi = await _isAndroidPackageInstalled('com.termux.api');
      final rootProbe = await _probeRootAvailability();
      final root = rootProbe?.available;
      final message = _runtimeStatusMessage(activeRuntime, runtimeCapabilities, rootProbe);
      if (!mounted) return;
      setState(() {
        _termuxInstalled = termux;
        _termuxApiInstalled = termuxApi;
        _rootAvailable = root;
        _runtimeHealth = runtimeHealth;
        _runtimeCapabilities = runtimeCapabilities;
        _runtimeMessage = message;
      });
      if (!silent) {
        final ready = activeRuntime?.ready == true;
        _addLog(
          ready ? 'Runtime ready' : 'Runtime needs setup',
          _runtimeMessage,
          ready ? Icons.verified_outlined : Icons.warning_amber_outlined,
          ready ? _mint : _amber,
        );
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _runtimeMessage = _compact(error.toString(), limit: 160);
      });
    } finally {
      if (mounted) setState(() => _runtimeChecking = false);
    }
  }

  String _runtimeStatusMessage(
    RuntimeHealth? activeRuntime,
    RuntimeCapabilities capabilities,
    _RootProbeResult? rootProbe,
  ) {
    final active = activeRuntime?.name ?? 'No runtime';
    final status = activeRuntime?.status ?? 'No runtime provider responded.';
    final caps = _runtimeCapabilityLabel(capabilities);
    final rootDetail = rootProbe?.detail;
    final rootSuffix = rootDetail != null && rootProbe?.available != true ? ' $rootDetail' : '';
    return '$active: $status Capabilities: $caps.$rootSuffix';
  }

  String _runtimeCapabilityLabel(RuntimeCapabilities capabilities) {
    final labels = <String>[
      if (capabilities.shell) 'shell',
      if (capabilities.git) 'git',
      if (capabilities.node) 'node',
      if (capabilities.python) 'python',
      if (capabilities.flutter) 'flutter',
      if (capabilities.androidBuild) 'apk',
      if (capabilities.pty) 'pty',
      if (capabilities.backgroundService) 'bg',
      if (capabilities.cloudBuild) 'cloud',
      if (capabilities.webViewPreview) 'webview',
    ];
    return labels.isEmpty ? 'webview-only' : labels.join(', ');
  }

  void _setTab(_HomeTab tab) {
    setState(() {
      _tab = tab;
      _selectedLayerIndex = switch (tab) {
        _HomeTab.control => 0,
        _HomeTab.ai => 2,
        _HomeTab.ship => 3,
        _HomeTab.guard => 4,
        _HomeTab.insight => 5,
      };
    });
  }

  void _runAction(_ModuleAction action, [_Capability? capability]) {
    switch (action) {
      case _ModuleAction.aiChat:
        _openChatSheet();
        break;
      case _ModuleAction.apiConfig:
        _showMessage('API configuration is at the top of this screen');
        break;
      case _ModuleAction.healthCheck:
        _checkHealth();
        break;
      case _ModuleAction.webDemo:
        _openMobileCodingLabSheet(autoGenerate: true);
        break;
      case _ModuleAction.githubTest:
        _openGitHubTestSheet();
        break;
      case _ModuleAction.diary:
        _openDiarySheet();
        break;
      case _ModuleAction.toolLab:
        _openToolLabSheet();
        break;
      case _ModuleAction.termuxCheck:
        _openTermuxSheet();
        break;
      case _ModuleAction.newFile:
        _openDraftSheet();
        break;
      case _ModuleAction.snippet:
        _openSnippetSheet();
        break;
      case _ModuleAction.project:
        unawaited(_openProjectSheet());
        break;
      case _ModuleAction.terminal:
        _openCommandSheet();
        break;
      case _ModuleAction.deepDive:
        unawaited(_openDeepDiveSheet());
        break;
      case _ModuleAction.build:
        _openBuildSheet();
        break;
      case _ModuleAction.githubRepoHub:
        unawaited(_openGitHubRepoHub());
        break;
      case _ModuleAction.larkCli:
        _openLarkCliSheet();
        break;
      case _ModuleAction.tokenUsage:
        _openManagementScreen('Token Usage', const ApiUsageScreen());
        break;
      case _ModuleAction.deviceTelemetry:
        _openManagementScreen('Device Telemetry', const DeviceTelemetryScreen());
        break;
      case _ModuleAction.downloadsShared:
        _openManagementScreen('Downloads / Shared folders', const DownloadsSharedFoldersScreen());
        break;
      case _ModuleAction.activityCenter:
        _openActionEvidenceCenterSheet();
        break;
      case _ModuleAction.inspect:
        if (capability != null) _openCapabilitySheet(capability);
        break;
    }
  }

  void _openActionEvidenceCenterSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: _panel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(10))),
      builder: (context) => const _ActionEvidenceCenterSheet(),
    );
  }

  void _openCapabilitySheet(_Capability capability) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
      builder: (context) => _CapabilitySheet(
        capability: capability,
        onRun: () {
          Navigator.pop(context);
          _runAction(capability.primaryAction, capability);
        },
        onCopy: () {
          Clipboard.setData(ClipboardData(text: capability.services.join('\n')));
          _showMessage('Service list copied');
        },
      ),
    );
  }

  void _openChatSheet() {
    if (_effectiveBaseUrl.isEmpty) {
      _showMessage('Configure Base URL first');
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
      builder: (context) => _ChatPanel(
        baseUrl: _effectiveBaseUrl,
        apiKey: _effectiveApiKey,
        model: _effectiveModel,
        providerPreset: _managedProviderActive ? _activeManagedProviderPreset : _detectProviderPreset(_effectiveBaseUrl, _effectiveModel),
        managedProviderPresets: _managedProviderPresets,
        relayUrl: _managedProviderActive ? _managedRelayUrl : '',
        relayToken: _managedProviderActive ? _managedRelayToken : '',
        browserOpenMode: _browserOpenMode,
        onLog: (title, detail, icon, color) => _addLog(title, detail, icon, color),
        onAgentPrompt: _handleAgentPrompt,
        onProviderPresetSelected: (preset) => unawaited(_selectProviderFromComposer(preset)),
      ),
    );
  }

  Future<void> _handleAgentPrompt(String prompt) async {
    final toolName = _agentToolNameForPrompt(prompt);
    _addLog('Agent process stayed in chat', toolName, Icons.psychology_alt_outlined, _violet);
  }

  void _openMobileCodingLabSheet({bool autoGenerate = false}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
      builder: (context) => _MobileCodingLabSheet(
        autoGenerate: autoGenerate,
        onOpenOnlineDemo: () => _openUrl(_demo2048Url, 'published 2048 demo'),
        onOpenGitHub: () => _openUrl(_githubTestUrl, 'GitHub test page'),
        onLog: (title, detail, icon, color) => _addLog(title, detail, icon, color),
      ),
    );
  }

  Future<void> _openUrl(String url, String label) async {
    try {
      final uri = Uri.parse(url);
      final opened = await _launchUrlWithBrowserMode(uri, _browserOpenMode);
      _addLog(
        opened ? 'Opened $label' : 'Failed to open $label',
        '$url · ${_browserOpenModeLabel(_browserOpenMode)}',
        opened ? Icons.open_in_browser_outlined : Icons.error_outline,
        opened ? _mint : _rose,
      );
      if (!opened) {
        _showMessage('Could not open $label');
      }
    } on Object catch (error) {
      _addLog('Open URL failed', _compact(error.toString(), limit: 120), Icons.error_outline, _rose);
      _showMessage('Could not open $label');
    }
  }

  Future<void> _openWorkspaceFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        _showMessage('File was not found on this phone');
        return;
      }
      final code = await file.readAsString();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: _panel,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(10))),
        builder: (context) => _CodeFileSheet(
          path: path,
          code: code,
          onOpenEditor: () => unawaited(_openWorkspaceFileInEditor(path, initialContent: code)),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      _showMessage(_compact(error.toString(), limit: 140));
    }
  }

  Future<void> _openWorkspaceFileInEditor(String path, {String? initialContent}) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EditorScreen(
          initialFilePath: path,
          initialContent: initialContent,
          fileName: p.basename(path),
        ),
      ),
    );
  }

  Future<void> _openWorkspaceFolder(String path) async {
    try {
      final root = await _mobileCodeProjectsRootDirectory();
      final folder = Directory(path);
      if (!await folder.exists()) {
        _showMessage('Project folder was not found on this phone');
        return;
      }
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: _panel,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(10))),
        builder: (context) => _ProjectFolderSheet(
          initialPath: folder.path,
          workspaceRoot: root.path,
          onOpenFile: (filePath) => unawaited(_openWorkspaceFile(filePath)),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      _showMessage(_compact(error.toString(), limit: 140));
    }
  }

  void _openManagementScreen(String label, Widget screen) {
    _addLog('Opened $label', 'Management surface route', Icons.dashboard_customize_outlined, _cyan);
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  Future<void> _openGitHubRepoHub() async {
    _addLog('Opened GitHub Repo Hub', 'Management surface route', Icons.dashboard_customize_outlined, _cyan);
    final request = await Navigator.of(context).push<GitHubRepoChatRequest>(
      MaterialPageRoute<GitHubRepoChatRequest>(builder: (_) => const GitHubRepoHubScreen()),
    );
    if (!mounted || request == null) return;
    final chat = await _focusChatPanel();
    if (chat == null) {
      _showMessage('Chat panel is still loading');
      return;
    }
    await chat.createSessionFromShell();
    await chat.bindRepoFromShell(request);
    await chat.setPromptFromShell(request.prompt);
    _addLog(
      'Repo chat ready',
      'Chat opened for ${request.repoFullName}.',
      Icons.chat_bubble_outline,
      _blue,
    );
  }

  void _openGitHubTestSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
      builder: (context) => _GitHubTestSheet(
        onOpenWeb: () => _openUrl(_githubTestUrl, 'GitHub test page'),
        onLog: (title, detail, icon, color) => _addLog(title, detail, icon, color),
      ),
    );
  }

  void _openDiarySheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
      builder: (context) => _DiarySheet(
        onLog: (title, detail, icon, color) => _addLog(title, detail, icon, color),
      ),
    );
  }

  void _openToolLabSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
      builder: (context) => _ToolLabSheet(
        baseUrl: _effectiveBaseUrl,
        apiKey: _effectiveApiKey,
        model: _effectiveModel,
        onOpen2048: () => _openMobileCodingLabSheet(autoGenerate: true),
        onOpenGitHubWeb: () => _openUrl(_githubTestUrl, 'GitHub test page'),
        onLog: (title, detail, icon, color) => _addLog(title, detail, icon, color),
      ),
    );
  }

  void _openTermuxSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
      builder: (context) => _RuntimeDiagnosticsSheet(
        runtimeManager: _runtimeManager,
        initialHealth: _runtimeHealth,
        initialCapabilities: _runtimeCapabilities,
        termuxInstalled: _termuxInstalled,
        termuxApiInstalled: _termuxApiInstalled,
        rootAvailable: _rootAvailable,
        onOpenInstall: () => _openUrl('https://f-droid.org/packages/com.termux/', 'External Termux install page'),
        onRefreshParent: () => _checkRuntime(),
        onLog: (title, detail, icon, color) => _addLog(title, detail, icon, color),
      ),
    );
  }

  void _openDraftSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
      builder: (context) => _DraftSheet(
        onCreate: (name, language) {
          setState(() {
            _drafts.insert(0, _DraftFile(name: name, language: language, createdAt: DateTime.now()));
          });
          _addLog('File draft created', '$language - $name', Icons.note_add_outlined, _cyan);
        },
      ),
    );
  }

  void _openSnippetSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
      builder: (context) => _SnippetSheet(
        onCreate: (title, language) {
          setState(() {
            _snippets.insert(0, _SnippetDraft(title: title, language: language, createdAt: DateTime.now()));
          });
          _addLog('Snippet captured', '$language - $title', Icons.data_object_outlined, _lime);
        },
      ),
    );
  }

  Future<void> _openProjectSheet() async {
    final workspaceRoot = (await _mobileCodeProjectsRootDirectory()).path;
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
      builder: (context) => _ProjectConsoleSheet(
        runtimeManager: _runtimeManager,
        defaultProjectPath: workspaceRoot,
        onLog: (title, detail, icon, color) => _addLog(title, detail, icon, color),
      ),
    );
  }

  void _openCommandSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
      builder: (context) => _RuntimeActionsSheet(
        icon: Icons.terminal_outlined,
        title: 'Runtime Actions',
        subtitle: 'Run structured mobile coding actions through the active RuntimeProvider.',
        runtimeManager: _runtimeManager,
        defaultPackageManager: 'npm',
        onLog: (title, detail, icon, color) => _addLog(title, detail, icon, color),
      ),
    );
  }

  Future<void> _openDeepDiveSheet() async {
    final workspaceRoot = (await _mobileCodeProjectsRootDirectory()).path;
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
      builder: (_) => _DeepDiveConsoleSheet(
        runtimeManager: _runtimeManager,
        defaultProjectPath: workspaceRoot,
        onLog: (title, detail, icon, color) => _addLog(title, detail, icon, color),
        onStartInChat: (prompt) {
          _addLog('Deep Dive started', 'Prompt sent to Chat Agent with RuntimeManager context', Icons.psychology_alt_outlined, _violet);
          unawaited(_usePromptShortcut(prompt, runAgent: true));
        },
      ),
    );
  }

  void _openBuildSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
      builder: (context) => _RuntimeActionsSheet(
        icon: Icons.rocket_launch_outlined,
        title: 'Build and Release Actions',
        subtitle: 'Install, test, build preview, commit, and publish through RuntimeManager.',
        runtimeManager: _runtimeManager,
        defaultPackageManager: 'flutter',
        onLog: (title, detail, icon, color) => _addLog(title, detail, icon, color),
      ),
    );
  }

  void _openLarkCliSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
      builder: (context) => _LarkCliDiagnosticsSheet(
        runtimeManager: _runtimeManager,
        onOpenDocs: () => _openUrl('https://github.com/larksuite/cli', 'Lark CLI docs'),
        onLog: (title, detail, icon, color) => _addLog(title, detail, icon, color),
      ),
    );
  }

  void _addLog(String title, String detail, IconData icon, Color color) {
    setState(() {
      _activity.insert(
        0,
        _ActivityLog(
          title: title,
          detail: detail,
          icon: icon,
          color: color,
          time: DateTime.now(),
        ),
      );
      if (_activity.length > 8) {
        _activity.removeLast();
      }
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _syncDrawerSessions(List<_ChatSession> sessions, String? activeSessionId) {
    if (!mounted) return;
    setState(() {
      _drawerSessions = List<_ChatSession>.unmodifiable(sessions);
      _drawerActiveSessionId = activeSessionId;
    });
  }

  void _openDrawer() {
    _scaffoldKey.currentState?.openDrawer();
  }

  Future<void> _closeDrawerIfOpen() async {
    final scaffold = _scaffoldKey.currentState;
    if (scaffold?.isDrawerOpen == true) {
      scaffold?.closeDrawer();
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
  }

  Future<_ChatPanelState?> _focusChatPanel() async {
    _setTab(_HomeTab.control);
    for (var attempt = 0; attempt < 4; attempt++) {
      final state = _chatPanelKey.currentState;
      if (state != null) return state;
      await Future<void>.delayed(const Duration(milliseconds: 24));
    }
    return _chatPanelKey.currentState;
  }

  Future<void> _newChatFromDrawer() async {
    await _closeDrawerIfOpen();
    final chat = await _focusChatPanel();
    if (chat == null) {
      _showMessage('Chat panel is still loading');
      return;
    }
    await chat.createSessionFromShell();
    _addLog('New chat created', 'A fresh conversation is ready.', Icons.add_comment_outlined, _mint);
  }

  Future<void> _selectChatFromDrawer(String id) async {
    await _closeDrawerIfOpen();
    final chat = await _focusChatPanel();
    if (chat == null) {
      _showMessage('Chat panel is still loading');
      return;
    }
    await chat.selectSessionFromShell(id);
  }

  Future<void> _usePromptShortcut(String prompt, {bool runAgent = false}) async {
    await _closeDrawerIfOpen();
    final chat = await _focusChatPanel();
    if (chat == null) {
      _showMessage('Chat panel is still loading');
      return;
    }
    await chat.setPromptFromShell(prompt, runAgent: runAgent);
  }

  int get _simpleTabIndex {
    return switch (_tab) {
      _HomeTab.control => 0,
      _HomeTab.ai => 0,
      _HomeTab.ship => 1,
      _HomeTab.guard => 2,
      _HomeTab.insight => 2,
    };
  }

  Widget _buildChatTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
          child: _MobileChatTopBar(
            title: 'MobileCode',
            onMenu: _openDrawer,
          ),
        ),
        Expanded(
          child: _ChatPanel(
            key: _chatPanelKey,
            baseUrl: _effectiveBaseUrl,
            apiKey: _effectiveApiKey,
            model: _effectiveModel,
            providerPreset: _managedProviderActive ? _activeManagedProviderPreset : _detectProviderPreset(_effectiveBaseUrl, _effectiveModel),
            managedProviderPresets: _managedProviderPresets,
            relayUrl: _managedProviderActive ? _managedRelayUrl : '',
            relayToken: _managedProviderActive ? _managedRelayToken : '',
            browserOpenMode: _browserOpenMode,
            embedded: true,
            onLog: (title, detail, icon, color) => _addLog(title, detail, icon, color),
            onAgentPrompt: _handleAgentPrompt,
            onProviderPresetSelected: (preset) => unawaited(_selectProviderFromComposer(preset)),
            onSessionsChanged: _syncDrawerSessions,
          ),
        ),
      ],
    );
  }

  Widget _buildCommandsTab() {
    final commands = [
      _CommandShortcut(
        icon: Icons.videogame_asset_outlined,
        title: '帮我做一个贪吃蛇游戏',
        subtitle: '填入提示词，Run Agent 后展示写代码、写文件、预览流程。',
        color: _mint,
        action: _ModuleAction.aiChat,
      ),
      _CommandShortcut(
        icon: Icons.grid_4x4_outlined,
        title: '做 2048 网页小游戏',
        subtitle: '生成本地 HTML/CSS/JS，并一键进入 Android WebView 预览。',
        color: _cyan,
        action: _ModuleAction.webDemo,
      ),
      _CommandShortcut(
        icon: Icons.edit_note_outlined,
        title: '做一个最小日记 App',
        subtitle: '验证 APK 内本地写入、读取、列表和空状态体验。',
        color: _amber,
        action: _ModuleAction.diary,
      ),
      _CommandShortcut(
        icon: Icons.note_add_outlined,
        title: '新建代码文件',
        subtitle: '为移动端工作区创建文件草稿，后续交给 agent 修改。',
        color: _violet,
        action: _ModuleAction.newFile,
      ),
      _CommandShortcut(
        icon: Icons.data_object_outlined,
        title: '保存代码片段',
        subtitle: '把常用片段存入本地 snippet 面板。',
        color: _lime,
        action: _ModuleAction.snippet,
      ),
      _CommandShortcut(
        icon: Icons.psychology_alt_outlined,
        title: '深潜一个任务',
        subtitle: '显示 agent 的计划、工具调用、观察和完成状态。',
        color: _rose,
        action: _ModuleAction.deepDive,
      ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      cacheExtent: 700,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        _SimpleHeader(
          title: 'Create',
          subtitle: 'Prompt shortcuts for mobile coding tasks.',
          leading: IconButton.filledTonal(
            tooltip: 'Open conversations',
            onPressed: _openDrawer,
            icon: const Icon(Icons.menu_rounded),
          ),
        ),
        const SizedBox(height: 12),
        _PromptLaunchPanel(onPrompt: _usePromptShortcut),
        const SizedBox(height: 12),
        for (final command in commands) ...[
          _CommandShortcutTile(
            command: command,
            onTap: () {
              if (command.title.contains('贪吃蛇')) {
                _usePromptShortcut('帮我在手机端创建一个可运行的贪吃蛇网页小游戏，生成 index.html、展示写代码过程，并用 WebView 预览。', runAgent: true);
              } else if (command.title.contains('2048')) {
                _usePromptShortcut('帮我创建一个 2048 网页小游戏，保存为 index.html，并打开本地 WebView 预览。', runAgent: true);
              } else {
                _runAction(command.action);
              }
            },
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildToolsTab() {
    final tools = [
      _CommandShortcut(
        icon: Icons.receipt_long_outlined,
        title: 'Activity / Logs',
        subtitle: 'Read recent action evidence and failures from one lightweight entry.',
        color: _violet,
        action: _ModuleAction.activityCenter,
      ),
      _CommandShortcut(
        icon: Icons.handyman_outlined,
        title: 'Tool tests',
        subtitle: '查看 tool list，并测试 provider、GitHub、WebView、storage、runtime、root。',
        color: _cyan,
        action: _ModuleAction.toolLab,
      ),
      _CommandShortcut(
        icon: Icons.terminal_outlined,
        title: 'Runtime providers',
        subtitle: '检查 Helper、External Termux fallback、root keepalive 和后端状态。',
        color: _amber,
        action: _ModuleAction.termuxCheck,
      ),
      _CommandShortcut(
        icon: Icons.hub_outlined,
        title: 'GitHub test',
        subtitle: '填写 GitHub token 后验证 /user、repo、Pages 能否联通。',
        color: _violet,
        action: _ModuleAction.githubTest,
      ),
      _CommandShortcut(
        icon: Icons.account_tree_outlined,
        title: 'GitHub Repo Hub',
        subtitle: '列出仓库、关注名单、本机工作区、Pages 和 Actions 状态。',
        color: _blue,
        action: _ModuleAction.githubRepoHub,
      ),
      _CommandShortcut(
        icon: Icons.folder_shared_outlined,
        title: 'Downloads / Shared folders',
        subtitle: '统一查看 Actions artifact 下载和 Runtime 同步共享目录。',
        color: _mint,
        action: _ModuleAction.downloadsShared,
      ),
      _CommandShortcut(
        icon: Icons.business_center_outlined,
        title: 'Lark CLI connector',
        subtitle: '受控检测 lark-cli、auth status 和推荐登录命令。',
        color: _lime,
        action: _ModuleAction.larkCli,
      ),
      _CommandShortcut(
        icon: Icons.token_outlined,
        title: 'Token Usage',
        subtitle: '查看 provider token、cache hit、估算费用和最近 run。',
        color: _violet,
        action: _ModuleAction.tokenUsage,
      ),
      _CommandShortcut(
        icon: Icons.speed_outlined,
        title: 'Device telemetry',
        subtitle: '手机 CPU、RAM、存储、电量、温度和 App 内存采样。',
        color: _cyan,
        action: _ModuleAction.deviceTelemetry,
      ),
      _CommandShortcut(
        icon: Icons.rocket_launch_outlined,
        title: 'Build / release',
        subtitle: '查看 GitHub Release、APK、iOS simulator 和 smoke report。',
        color: _rose,
        action: _ModuleAction.build,
      ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      cacheExtent: 700,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        _SimpleHeader(
          title: 'Tools',
          subtitle: 'Phone runtime, backend bridge, GitHub, and release checks.',
          leading: IconButton.filledTonal(
            tooltip: 'Open conversations',
            onPressed: _openDrawer,
            icon: const Icon(Icons.menu_rounded),
          ),
        ),
        const SizedBox(height: 12),
        _RuntimePermissionBanner(
          activeRuntimeName: _activeRuntimeName,
          ready: _runtimeReady,
          capabilitiesLabel: _runtimeCapabilityLabel(_runtimeCapabilities),
          checking: _runtimeChecking,
          message: _runtimeMessage,
          onCheck: () => _checkRuntime(),
          onOpenRuntime: _openTermuxSheet,
        ),
        const SizedBox(height: 12),
        _ManagementSurfacePanel(
          onOpenAgent: () => _openManagementScreen('Agent Manager', const AgentDashboardScreen()),
          onOpenRoles: () => _openManagementScreen(
            'Role Library',
            RoleManagerScreen(onPolishRoleIntent: _polishRoleIntent),
          ),
          onOpenSkills: () => _openManagementScreen('Skill Manager', const SkillManagerScreen()),
          onOpenMcp: () => _openManagementScreen('MCP Manager', const McpManagerScreen()),
          onOpenMemory: () => _openManagementScreen('Memory Manager', const MemoryManagerScreen()),
          onOpenHooks: () => _openManagementScreen('Hook Registry', const HookRegistryScreen()),
          onOpenUsage: () => _openManagementScreen('Token Usage', const ApiUsageScreen()),
          onOpenDevice: () => _openManagementScreen('Device Telemetry', const DeviceTelemetryScreen()),
        ),
        const SizedBox(height: 12),
        for (final tool in tools) ...[
          _CommandShortcutTile(
            command: tool,
            onTap: () => _runAction(tool.action),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildSettingsTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      cacheExtent: 700,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        _SimpleHeader(
          title: 'Settings',
          subtitle: 'Runtime, model, release, and advanced capability surfaces.',
          leading: IconButton.filledTonal(
            tooltip: 'Open conversations',
            onPressed: _openDrawer,
            icon: const Icon(Icons.menu_rounded),
          ),
        ),
        const SizedBox(height: 12),
        _ApiConfigCard(
          baseUrlController: _baseUrlController,
          apiKeyController: _apiKeyController,
          modelController: _modelController,
          saving: _saving,
          flavor: _flavor,
          providerPreset: _detectProviderPreset(_effectiveBaseUrl, _effectiveModel),
          managedProviderAvailable: _managedProviderAvailable,
          managedProviderActive: _managedProviderActive,
          onPreset: _applyDefaultProvider,
          onProviderPreset: _applyProviderPreset,
          onUseManagedProvider: () => unawaited(_setProviderMode(useCustom: false)),
          onUseCustomProvider: () => unawaited(_setProviderMode(useCustom: true)),
          onSave: _saveConfig,
          onHealth: _checkHealth,
        ),
        const SizedBox(height: 12),
        _HealthCard(
          state: _healthState,
          message: _healthMessage,
          flavor: _flavor,
          onCheck: _checkHealth,
        ),
        const SizedBox(height: 12),
        _ThemePreferenceCard(
          selectedTheme: _brandTheme,
          onChanged: (value) => unawaited(_setBrandTheme(value)),
        ),
        const SizedBox(height: 12),
        _BrowserOpenPreferenceCard(
          selectedMode: _browserOpenMode,
          onChanged: (value) => unawaited(_setBrowserOpenMode(value)),
        ),
        const SizedBox(height: 12),
        _WorkspaceRootCard(
          onOpenFolder: (path) => unawaited(_openWorkspaceFolder(path)),
        ),
        const SizedBox(height: 12),
        _SideloadStatusPanel(
          managedProviderActive: _managedProviderActive,
          onOpenRelease: () => _openUrl(_releaseUrl, 'GitHub Release'),
          onOpenAndroidReport: () => _openUrl(_androidSmokeRunUrl, 'Android smoke report'),
          onOpenIosReport: () => _openUrl(_iosSimulatorRunUrl, 'iOS simulator report'),
        ),
        const SizedBox(height: 12),
        _Panel(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.account_tree_outlined, color: _cyan),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Advanced backend map', style: TextStyle(color: _text, fontWeight: FontWeight.w800)),
                    SizedBox(height: 2),
                    Text('Hidden by default. Keep the product chat-first.', style: TextStyle(color: _muted, fontSize: 12)),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _showCapabilityMap = !_showCapabilityMap),
                icon: Icon(_showCapabilityMap ? Icons.expand_less_outlined : Icons.expand_more_outlined),
                label: Text(_showCapabilityMap ? 'Hide' : 'Show'),
              ),
            ],
          ),
        ),
        if (_showCapabilityMap) ...[
          const SizedBox(height: 14),
          _LayerSelector(
            layers: _layers,
            selectedIndex: _safeLayerIndex,
            onSelected: (index) => setState(() => _selectedLayerIndex = index),
          ),
          const SizedBox(height: 12),
          _LayerHeader(layer: _activeLayer),
          const SizedBox(height: 10),
          for (final capability in _activeLayer.capabilities) ...[
            _CapabilityCard(
              capability: capability,
              layerColor: _activeLayer.color,
              onRun: () => _runAction(capability.primaryAction, capability),
              onInspect: () => _openCapabilitySheet(capability),
            ),
            const SizedBox(height: 10),
          ],
        ],
        const SizedBox(height: 14),
        _OperationsBoard(
          activity: _activity,
          drafts: _drafts,
          snippets: _snippets,
          healthState: _healthState,
          layerCount: _layers.length,
          serviceCount: _layers.fold<int>(0, (sum, layer) => sum + layer.serviceCount),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      key: _scaffoldKey,
      resizeToAvoidBottomInset: true,
      backgroundColor: _bg,
      drawer: _MobileCodeDrawer(
        sessions: _drawerSessions,
        activeSessionId: _drawerActiveSessionId,
        runtimeReady: _runtimeReady,
        runtimeLabel: _runtimeDrawerLabel,
        onNewChat: _newChatFromDrawer,
        onSelectSession: _selectChatFromDrawer,
        onPrompt: _usePromptShortcut,
        onOpenSettings: () {
          Navigator.of(context).pop();
          _setTab(_HomeTab.guard);
        },
        onOpenTools: () {
          Navigator.of(context).pop();
          _setTab(_HomeTab.ship);
        },
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: IndexedStack(
                index: _simpleTabIndex,
                children: [
                  _buildChatTab(),
                  _buildToolsTab(),
                  _buildSettingsTab(),
                ],
              ),
            ),
            if (!keyboardOpen) _BottomNav(tab: _tab, onChanged: _setTab),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.healthState,
    required this.flavor,
    required this.onChat,
  });

  final _HealthState healthState;
  final _ApiFlavor flavor;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _panel,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _line),
          ),
          child: const Icon(Icons.code_rounded, color: _mint),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MobileCode',
                style: TextStyle(color: _text, fontSize: 28, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 2),
              Text(
                'Phone-native AI coding harness',
                style: TextStyle(color: _muted, fontSize: 13),
              ),
            ],
          ),
        ),
        Tooltip(
          message: 'Open AI Chat',
          child: IconButton.filledTonal(
            onPressed: onChat,
            icon: const Icon(Icons.forum_outlined),
          ),
        ),
      ],
    );
  }
}

class _SimpleHeader extends StatelessWidget {
  const _SimpleHeader({
    required this.title,
    required this.subtitle,
    this.leading,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        leading ??
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _panel,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _line),
              ),
              child: const Icon(Icons.code_rounded, color: _mint),
            ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: _text, fontSize: 24, fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(color: _muted, fontSize: 12)),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 10),
          trailing!,
        ],
      ],
    );
  }
}

class _MobileChatTopBar extends StatelessWidget {
  const _MobileChatTopBar({
    required this.title,
    required this.onMenu,
  });

  final String title;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Open conversations',
          onPressed: onMenu,
          icon: const Icon(Icons.menu_rounded, color: _text, size: 28),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _text, fontSize: 20, fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(width: 6),
        const _CpuTelemetryChip(),
      ],
    );
  }
}

class _CpuTelemetryChip extends StatefulWidget {
  const _CpuTelemetryChip();

  @override
  State<_CpuTelemetryChip> createState() => _CpuTelemetryChipState();
}

class _CpuTelemetryChipState extends State<_CpuTelemetryChip> {
  late final Stream<DeviceTelemetrySnapshot> _stream;

  @override
  void initState() {
    super.initState();
    _stream = DeviceTelemetryService.instance.watchTelemetry(interval: const Duration(seconds: 2));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DeviceTelemetrySnapshot>(
      stream: _stream,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final label = data == null ? 'CPU --' : '${data.cpuUsagePercent.clamp(0, 100).toStringAsFixed(0)}%';
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: data == null ? null : () => _showTelemetryDetails(context, data),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: _mint.withOpacity(0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _mint.withOpacity(0.34)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.speed_outlined, size: 13, color: _mint),
                  const SizedBox(width: 4),
                  Text(label, style: const TextStyle(color: _mint, fontSize: 11, fontWeight: FontWeight.w900)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showTelemetryDetails(BuildContext context, DeviceTelemetrySnapshot data) {
    final deviceLabel = [data.manufacturer, data.model]
        .where((item) => item.trim().isNotEmpty)
        .join(' ')
        .trim();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _panel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(color: _line, borderRadius: BorderRadius.circular(99)),
                ),
              ),
              const SizedBox(height: 14),
              const Row(
                children: [
                  Icon(Icons.speed_outlined, color: _mint, size: 18),
                  SizedBox(width: 8),
                  Text('Device telemetry', style: TextStyle(color: _text, fontSize: 18, fontWeight: FontWeight.w900)),
                ],
              ),
              const SizedBox(height: 12),
              _TelemetryDetailRow(label: 'CPU', value: '${data.cpuUsagePercent.clamp(0, 100).toStringAsFixed(0)}% · ${data.cpuCores} cores'),
              _TelemetryDetailRow(label: 'Memory', value: data.totalMemoryMb > 0 ? '${data.availableMemoryMb} MB free / ${data.totalMemoryMb} MB' : 'Fallback unavailable'),
              _TelemetryDetailRow(label: 'App RSS / Heap', value: '${data.appRssMb} MB / ${data.appHeapMb} MB'),
              _TelemetryDetailRow(label: 'Storage', value: data.storageTotalMb > 0 ? '${data.storageFreeMb} MB free / ${data.storageTotalMb} MB' : 'Unavailable'),
              _TelemetryDetailRow(
                label: 'Battery',
                value: data.batteryLevel >= 0
                    ? '${data.batteryLevel}%${data.batteryCharging ? ' · charging' : ''}${data.batteryTemperatureC > 0 ? ' · ${data.batteryTemperatureC.toStringAsFixed(1)}°C' : ''}'
                    : 'Unavailable',
              ),
              _TelemetryDetailRow(label: 'Device', value: deviceLabel.isEmpty ? data.platform : deviceLabel),
              if (data.fallback)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Using Flutter fallback telemetry. Android native telemetry is unavailable in this build/runtime.',
                    style: TextStyle(color: _amber, fontSize: 12, height: 1.35),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TelemetryDetailRow extends StatelessWidget {
  const _TelemetryDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: const TextStyle(color: _muted, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: _text, fontSize: 12, height: 1.3)),
          ),
        ],
      ),
    );
  }
}

class _MobileCodeDrawer extends StatelessWidget {
  const _MobileCodeDrawer({
    required this.sessions,
    required this.activeSessionId,
    required this.runtimeReady,
    required this.runtimeLabel,
    required this.onNewChat,
    required this.onSelectSession,
    required this.onPrompt,
    required this.onOpenSettings,
    required this.onOpenTools,
  });

  final List<_ChatSession> sessions;
  final String? activeSessionId;
  final bool runtimeReady;
  final String runtimeLabel;
  final VoidCallback onNewChat;
  final ValueChanged<String> onSelectSession;
  final Future<void> Function(String prompt, {bool runAgent}) onPrompt;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenTools;

  @override
  Widget build(BuildContext context) {
    final runtimeColor = runtimeReady ? _mint : _amber;

    return Drawer(
      width: MediaQuery.of(context).size.width.clamp(280, 360).toDouble(),
      backgroundColor: _bg,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 14, 10),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('MobileCode', style: TextStyle(color: _text, fontSize: 24, fontWeight: FontWeight.w900)),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'New chat',
                    onPressed: onNewChat,
                    icon: const Icon(Icons.edit_square),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _Panel(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.admin_panel_settings_outlined, color: runtimeColor, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(runtimeLabel, style: const TextStyle(color: _muted, fontSize: 12, height: 1.3)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _DrawerAction(
              icon: Icons.add_comment_outlined,
              label: '新会话',
              onTap: onNewChat,
            ),
            _DrawerAction(
              icon: Icons.videogame_asset_outlined,
              label: '帮我做贪吃蛇游戏',
              onTap: () => onPrompt('帮我在手机端创建一个可运行的贪吃蛇网页小游戏，生成 index.html、展示写代码过程，并用 WebView 预览。', runAgent: true),
            ),
            _DrawerAction(
              icon: Icons.handyman_outlined,
              label: '工具与权限',
              onTap: onOpenTools,
            ),
            _DrawerAction(
              icon: Icons.tune_outlined,
              label: '模型与设置',
              onTap: onOpenSettings,
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 18, 18, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Recent chats', style: TextStyle(color: _faint, fontSize: 12, fontWeight: FontWeight.w900)),
              ),
            ),
            Expanded(
              child: sessions.isEmpty
                  ? Padding(
                      padding: EdgeInsets.all(18),
                      child: Text(
                        activeSessionId == null ? 'Loading chat history...' : 'No chat history yet',
                        style: const TextStyle(color: _muted),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                      itemCount: sessions.length,
                      itemBuilder: (context, index) {
                        final session = sessions[index];
                        return _DrawerSessionTile(
                          session: session,
                          selected: session.id == activeSessionId,
                          onTap: () => onSelectSession(session.id),
                        );
                      },
                    ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: _line)),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 16,
                    backgroundColor: _panelSoft,
                    child: Icon(Icons.person_outline, color: _mint, size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Local user', style: TextStyle(color: _text, fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                    tooltip: 'Settings',
                    onPressed: onOpenSettings,
                    icon: const Icon(Icons.settings_outlined, color: _muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerAction extends StatelessWidget {
  const _DrawerAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: _text),
      title: Text(label, style: const TextStyle(color: _text, fontWeight: FontWeight.w800)),
      onTap: onTap,
      minLeadingWidth: 26,
    );
  }
}

class _DrawerSessionTile extends StatelessWidget {
  const _DrawerSessionTile({
    required this.session,
    required this.selected,
    required this.onTap,
  });

  final _ChatSession session;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      selected: selected,
      selectedTileColor: _mint.withOpacity(0.10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      leading: CircleAvatar(
        radius: 15,
        backgroundColor: selected ? _mint.withOpacity(0.18) : _panelSoft,
        child: Icon(Icons.chat_bubble_outline, color: selected ? _mint : _muted, size: 16),
      ),
      title: Text(
        session.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: selected ? _text : _muted, fontWeight: FontWeight.w800),
      ),
      subtitle: Text(_sessionTurnLabel(session), style: const TextStyle(color: _faint, fontSize: 11)),
      onTap: onTap,
    );
  }
}

class _RuntimePermissionBanner extends StatelessWidget {
  const _RuntimePermissionBanner({
    required this.activeRuntimeName,
    required this.ready,
    required this.capabilitiesLabel,
    required this.checking,
    required this.message,
    required this.onCheck,
    required this.onOpenRuntime,
  });

  final String activeRuntimeName;
  final bool ready;
  final String capabilitiesLabel;
  final bool checking;
  final String message;
  final VoidCallback onCheck;
  final VoidCallback onOpenRuntime;

  @override
  Widget build(BuildContext context) {
    final color = ready ? _mint : _amber;
    final title = ready ? 'Runtime ready' : 'Runtime setup needed';
    final statusLine = '$title · $activeRuntimeName · $capabilitiesLabel';
    return _Panel(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          Icon(ready ? Icons.verified_outlined : Icons.hub_outlined, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  statusLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 11, height: 1.2),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Open runtime diagnostics',
            visualDensity: VisualDensity.compact,
            onPressed: onOpenRuntime,
            icon: Icon(Icons.monitor_heart_outlined, color: _violet, size: 18),
          ),
          IconButton(
            tooltip: 'Check runtime',
            visualDensity: VisualDensity.compact,
            onPressed: checking ? null : onCheck,
            icon: checking
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_outlined, size: 18),
          ),
        ],
      ),
    );
  }
}

class _ThemePreferenceCard extends StatelessWidget {
  const _ThemePreferenceCard({
    required this.selectedTheme,
    required this.onChanged,
  });

  final String selectedTheme;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = selectedTheme == 'claudeYellow' ? 'claudeYellow' : 'codexBlue';
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _blue.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _line),
                ),
                child: const Icon(Icons.palette_outlined, color: _blue, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '视觉主题',
                      style: TextStyle(
                        color: _text,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Codex Blue 默认适合构建，Claude Yellow 适合阅读和复盘。',
                      style: TextStyle(color: _muted, fontSize: 12, height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ThemeChoiceChip(
                id: 'codexBlue',
                label: 'Codex Blue',
                colors: const [Color(0xFF2555FF), Color(0xFF16B9C7)],
                selected: selected == 'codexBlue',
                onTap: onChanged,
              ),
              _ThemeChoiceChip(
                id: 'claudeYellow',
                label: 'Claude Yellow',
                colors: const [Color(0xFFD97706), Color(0xFFFFB86B)],
                selected: selected == 'claudeYellow',
                onTap: onChanged,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BrowserOpenPreferenceCard extends StatelessWidget {
  const _BrowserOpenPreferenceCard({
    required this.selectedMode,
    required this.onChanged,
  });

  final String selectedMode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = _normalizeBrowserOpenMode(selectedMode);
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _amber.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _line),
                ),
                child: const Icon(Icons.open_in_browser_outlined, color: _amber, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '浏览器打开方式',
                      style: TextStyle(color: _text, fontSize: 16, fontWeight: FontWeight.w900),
                    ),
                    SizedBox(height: 3),
                    Text(
                      '网页链接可用系统默认浏览器或 App 内浏览器；本地 HTML 仍可用 WebView 预览。',
                      style: TextStyle(color: _muted, fontSize: 12, height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ThemeChoiceChip(
                id: _browserOpenModeSystem,
                label: '系统默认浏览器',
                colors: const [Color(0xFFB7791F), Color(0xFFFFB86B)],
                selected: selected == _browserOpenModeSystem,
                onTap: onChanged,
              ),
              _ThemeChoiceChip(
                id: _browserOpenModeInApp,
                label: 'App 内浏览器',
                colors: const [Color(0xFF7557E8), Color(0xFF16B9C7)],
                selected: selected == _browserOpenModeInApp,
                onTap: onChanged,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WorkspaceRootCard extends StatelessWidget {
  const _WorkspaceRootCard({required this.onOpenFolder});

  final ValueChanged<String> onOpenFolder;

  Future<void> _copyPath(BuildContext context, String path) async {
    await Clipboard.setData(ClipboardData(text: path));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Workspace path copied.')));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Directory>(
      future: _mobileCodeProjectsRootDirectory(),
      builder: (context, snapshot) {
        final path = snapshot.data?.path ?? 'Preparing MobileCode workspace...';
        return _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _mint.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _line),
                    ),
                    child: const Icon(Icons.folder_special_outlined, color: _mint, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('MobileCode Projects', style: TextStyle(color: _text, fontSize: 16, fontWeight: FontWeight.w900)),
                        SizedBox(height: 3),
                        Text(
                          'Generated pages and GitHub clone/import projects should live under this app-owned workspace.',
                          style: TextStyle(color: _muted, fontSize: 12, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SelectableText(
                path,
                style: const TextStyle(color: _muted, fontSize: 12, height: 1.35),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: snapshot.hasData ? () => onOpenFolder(snapshot.data!.path) : null,
                    icon: const Icon(Icons.folder_open_outlined, size: 16),
                    label: const Text('打开工程文件夹'),
                  ),
                  OutlinedButton.icon(
                    onPressed: snapshot.hasData ? () => unawaited(_copyPath(context, snapshot.data!.path)) : null,
                    icon: const Icon(Icons.copy_outlined, size: 16),
                    label: const Text('复制路径'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ThemeChoiceChip extends StatelessWidget {
  const _ThemeChoiceChip({
    required this.id,
    required this.label,
    required this.colors,
    required this.selected,
    required this.onTap,
  });

  final String id;
  final String label;
  final List<Color> colors;
  final bool selected;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final primary = colors.first;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => onTap(id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? primary.withOpacity(0.10) : _panel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? primary.withOpacity(0.55) : _line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: colors),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: primary.withOpacity(0.22),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 9),
            Text(
              label,
              style: TextStyle(
                color: selected ? primary : _text,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 7),
              Icon(Icons.check_circle, color: primary, size: 16),
            ],
          ],
        ),
      ),
    );
  }
}

class _SideloadStatusPanel extends StatelessWidget {
  const _SideloadStatusPanel({
    required this.managedProviderActive,
    required this.onOpenRelease,
    required this.onOpenAndroidReport,
    required this.onOpenIosReport,
  });

  final bool managedProviderActive;
  final VoidCallback onOpenRelease;
  final VoidCallback onOpenAndroidReport;
  final VoidCallback onOpenIosReport;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _mint.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _mint.withOpacity(0.34)),
                ),
                child: const Icon(Icons.verified_outlined, color: _mint, size: 19),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('GitHub install build', style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 15)),
                    SizedBox(height: 2),
                    Text(_releaseBuildLabel, style: TextStyle(color: _muted, fontSize: 12)),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: onOpenRelease,
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('Release'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusActionChip(
                label: 'Android smoke passed',
                icon: Icons.android_outlined,
                color: _mint,
                onTap: onOpenAndroidReport,
              ),
              _StatusActionChip(
                label: 'iOS simulator passed',
                icon: Icons.phone_iphone_outlined,
                color: _cyan,
                onTap: onOpenIosReport,
              ),
              _StatusActionChip(
                label: managedProviderActive ? 'Managed model active' : 'Bring your key',
                icon: managedProviderActive ? Icons.lock_outline : Icons.key_outlined,
                color: managedProviderActive ? _amber : _faint,
                onTap: onOpenRelease,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusActionChip extends StatelessWidget {
  const _StatusActionChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withOpacity(0.09),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.28)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 15),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

class _FocusPanel extends StatelessWidget {
  const _FocusPanel({
    required this.tab,
    required this.healthState,
    required this.onPrimary,
    required this.onSecondary,
  });

  final _HomeTab tab;
  final _HealthState healthState;
  final VoidCallback onPrimary;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) {
    final accent = _focusColor(tab);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withOpacity(0.30)),
      ),
      child: Row(
        children: [
          Icon(_focusIcon(tab), color: accent, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _focusTitle(tab),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _text, fontSize: 16, fontWeight: FontWeight.w900),
                      ),
                    ),
                    _MiniChip(label: _focusHealthLabel(healthState), color: _healthColor(healthState)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _focusSubtitle(tab),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 12, height: 1.32),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton.filledTonal(
                tooltip: _focusPrimaryLabel(tab),
                onPressed: onPrimary,
                icon: Icon(_focusPrimaryIcon(tab), size: 18),
              ),
              const SizedBox(height: 6),
              IconButton.outlined(
                tooltip: _focusSecondaryLabel(tab),
                onPressed: onSecondary,
                icon: Icon(_focusSecondaryIcon(tab), size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ApiConfigCard extends StatelessWidget {
  const _ApiConfigCard({
    required this.baseUrlController,
    required this.apiKeyController,
    required this.modelController,
    required this.saving,
    required this.flavor,
    required this.providerPreset,
    required this.managedProviderAvailable,
    required this.managedProviderActive,
    required this.onPreset,
    required this.onProviderPreset,
    required this.onUseManagedProvider,
    required this.onUseCustomProvider,
    required this.onSave,
    required this.onHealth,
  });

  final TextEditingController baseUrlController;
  final TextEditingController apiKeyController;
  final TextEditingController modelController;
  final bool saving;
  final _ApiFlavor flavor;
  final _ProviderPreset providerPreset;
  final bool managedProviderAvailable;
  final bool managedProviderActive;
  final VoidCallback onPreset;
  final ValueChanged<_ProviderPreset> onProviderPreset;
  final VoidCallback onUseManagedProvider;
  final VoidCallback onUseCustomProvider;
  final VoidCallback onSave;
  final VoidCallback onHealth;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune_outlined, color: _mint),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'API Configuration',
                  style: TextStyle(color: _text, fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              if (!managedProviderActive) ...[
                Tooltip(
                  message: 'Use Mimo Anthropic preset',
                  child: IconButton.filledTonal(
                    onPressed: onPreset,
                    icon: const Icon(Icons.auto_fix_high_outlined, size: 18),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              _Pill(
                label: _flavorLabel(flavor),
                icon: flavor == _ApiFlavor.anthropic ? Icons.hub_outlined : Icons.api_outlined,
                color: flavor == _ApiFlavor.anthropic ? _amber : _cyan,
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (managedProviderActive) ...[
            const _InlineStatus(
              icon: Icons.admin_panel_settings_outlined,
              label: 'Managed debug provider active - credentials are hidden in the UI.',
              color: _mint,
            ),
            const SizedBox(height: 10),
            const Text(
              'MobileCode is using bundled managed credentials by default. You can switch to Custom Provider when you need your own Base URL, key, or model.',
              style: TextStyle(color: _muted, fontSize: 12, height: 1.35),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onUseCustomProvider,
                    icon: const Icon(Icons.tune_outlined),
                    label: const Text('Use Custom'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onHealth,
                    icon: const Icon(Icons.monitor_heart_outlined),
                    label: const Text('Check Managed'),
                  ),
                ),
              ],
            ),
          ] else ...[
          if (managedProviderAvailable) ...[
            _InlineStatus(
              icon: Icons.tune_outlined,
              label: 'Custom provider override is active. Managed provider remains available as fallback.',
              color: _cyan,
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onUseManagedProvider,
              icon: const Icon(Icons.admin_panel_settings_outlined),
              label: const Text('Use Managed Provider'),
            ),
            const SizedBox(height: 12),
          ],
          const Text(
            'Provider',
            style: TextStyle(color: _muted, fontSize: 12, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in _ProviderPreset.values)
                ChoiceChip(
                  label: Text(_providerPresetLabel(preset)),
                  selected: providerPreset == preset,
                  onSelected: (_) => onProviderPreset(preset),
                  avatar: Icon(
                    preset == _ProviderPreset.custom
                        ? Icons.tune_outlined
                        : preset == _ProviderPreset.openAi
                            ? Icons.api_outlined
                            : preset == _ProviderPreset.deepSeek
                                ? Icons.psychology_alt_outlined
                                : Icons.hub_outlined,
                    size: 16,
                    color: providerPreset == preset ? _blue : _muted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: baseUrlController,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Base URL',
              hintText: _defaultBaseUrl,
              prefixIcon: Icon(Icons.link_outlined),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: apiKeyController,
            obscureText: true,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'API Key',
              hintText: 'sk-... or provider token',
              prefixIcon: Icon(Icons.key_outlined),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: modelController,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Model',
              hintText: _defaultModel,
              prefixIcon: Icon(Icons.memory_outlined),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose Custom for any OpenAI-compatible or Anthropic-compatible endpoint. Paste your API key locally; it is never shipped inside the APK.',
            style: TextStyle(color: _muted, fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: saving ? null : onSave,
                  icon: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(saving ? 'Saving' : 'Save'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onHealth,
                  icon: const Icon(Icons.monitor_heart_outlined),
                  label: const Text('Check'),
                ),
              ),
            ],
          ),
          ],
        ],
      ),
    );
  }
}

class _HealthCard extends StatelessWidget {
  const _HealthCard({
    required this.state,
    required this.message,
    required this.flavor,
    required this.onCheck,
  });

  final _HealthState state;
  final String message;
  final _ApiFlavor flavor;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      _HealthState.healthy => _mint,
      _HealthState.failed => _rose,
      _HealthState.checking => _amber,
      _HealthState.unknown => _faint,
    };
    final label = switch (state) {
      _HealthState.healthy => 'Healthy',
      _HealthState.failed => 'Unhealthy',
      _HealthState.checking => 'Checking',
      _HealthState.unknown => 'Unknown',
    };
    return _Panel(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [BoxShadow(color: color.withOpacity(0.35), blurRadius: 12)],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Provider Health - $label',
                  style: const TextStyle(color: _text, fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _Pill(
            label: _flavorLabel(flavor),
            icon: Icons.route_outlined,
            color: flavor == _ApiFlavor.anthropic ? _amber : _cyan,
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: 'Run health check',
            child: IconButton(
              onPressed: state == _HealthState.checking ? null : onCheck,
              icon: const Icon(Icons.refresh_outlined),
            ),
          ),
        ],
      ),
    );
  }
}

class _DemoLabPanel extends StatelessWidget {
  const _DemoLabPanel({
    required this.onOpen2048,
    required this.onGitHub,
    required this.onDiary,
    required this.onChat,
    required this.onTools,
    required this.onTermux,
  });

  final VoidCallback onOpen2048;
  final VoidCallback onGitHub;
  final VoidCallback onDiary;
  final VoidCallback onChat;
  final VoidCallback onTools;
  final VoidCallback onTermux;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.science_outlined, color: _mint),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Demo Lab', style: TextStyle(color: _text, fontSize: 20, fontWeight: FontWeight.w900)),
                    SizedBox(height: 2),
                    Text('The focused path: play, connect GitHub, build diary, chat with memory, test tools, check runtime.', style: TextStyle(color: _muted, fontSize: 12, height: 1.35)),
                  ],
                ),
              ),
              _Pill(label: 'Priority', icon: Icons.flag_outlined, color: _amber),
            ],
          ),
          const SizedBox(height: 14),
          _HeroDemoTile(
            title: 'Agent codes 2048',
            subtitle: 'Generate a real local HTML/CSS/JS project on the phone, save it, then preview it inside MobileCode WebView.',
            icon: Icons.grid_4x4_outlined,
            color: _mint,
            primaryLabel: 'Code + preview',
            secondaryLabel: 'GitHub test',
            onPrimary: onOpen2048,
            onSecondary: onGitHub,
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 680 ? 4 : 2;
              final items = [
                _DemoAction(Icons.edit_note_outlined, 'Diary APK', 'Local diary demo inside this APK', _ModuleAction.diary, _amber),
                _DemoAction(Icons.forum_outlined, 'Chat Memory', 'Conversation list and context', _ModuleAction.aiChat, _mint),
                _DemoAction(Icons.handyman_outlined, 'Tool Tests', 'Run mobile tool probes', _ModuleAction.toolLab, _cyan),
                _DemoAction(Icons.terminal_outlined, 'Runtime', 'Check Helper and Runtime fallback setup', _ModuleAction.termuxCheck, _lime),
              ];
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: columns == 2 ? 1.55 : 1.25,
                ),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return _DemoActionTile(
                    item: item,
                    onTap: switch (item.action) {
                      _ModuleAction.diary => onDiary,
                      _ModuleAction.aiChat => onChat,
                      _ModuleAction.toolLab => onTools,
                      _ModuleAction.termuxCheck => onTermux,
                      _ => onOpen2048,
                    },
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HeroDemoTile extends StatelessWidget {
  const _HeroDemoTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.onPrimary,
    required this.onSecondary,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String primaryLabel;
  final String secondaryLabel;
  final VoidCallback onPrimary;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title, style: const TextStyle(color: _text, fontSize: 18, fontWeight: FontWeight.w900)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(subtitle, style: const TextStyle(color: _muted, fontSize: 12, height: 1.4)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onPrimary,
                  icon: const Icon(Icons.open_in_browser_outlined),
                  label: Text(primaryLabel),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onSecondary,
                  icon: const Icon(Icons.hub_outlined),
                  label: Text(secondaryLabel),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DemoAction {
  const _DemoAction(this.icon, this.title, this.subtitle, this.action, this.color);

  final IconData icon;
  final String title;
  final String subtitle;
  final _ModuleAction action;
  final Color color;
}

class _CommandShortcut {
  const _CommandShortcut({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final _ModuleAction action;
}

class _CommandShortcutTile extends StatelessWidget {
  const _CommandShortcutTile({required this.command, required this.onTap});

  final _CommandShortcut command;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: _Panel(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: command.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: command.color.withOpacity(0.28)),
                ),
                child: Icon(command.icon, color: command.color, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(command.title, style: const TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 15)),
                    const SizedBox(height: 4),
                    Text(command.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 12, height: 1.35)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_outlined, color: _faint),
            ],
          ),
        ),
      ),
    );
  }
}

class _DemoActionTile extends StatelessWidget {
  const _DemoActionTile({required this.item, required this.onTap});

  final _DemoAction item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _panelSoft,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(item.icon, color: item.color, size: 24),
              const Spacer(),
              Text(item.title, style: const TextStyle(color: _text, fontWeight: FontWeight.w900)),
              const SizedBox(height: 3),
              Text(
                item.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _muted, fontSize: 11, height: 1.25),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileCodingLabSheet extends StatefulWidget {
  const _MobileCodingLabSheet({
    required this.autoGenerate,
    required this.onOpenOnlineDemo,
    required this.onOpenGitHub,
    required this.onLog,
  });

  final bool autoGenerate;
  final VoidCallback onOpenOnlineDemo;
  final VoidCallback onOpenGitHub;
  final void Function(String title, String detail, IconData icon, Color color) onLog;

  @override
  State<_MobileCodingLabSheet> createState() => _MobileCodingLabSheetState();
}

class _MobileCodingLabSheetState extends State<_MobileCodingLabSheet> {
  String? _projectPath;
  String? _transcriptPath;
  String? _html;
  String _stage = 'Idle';
  int? _lastGenerateMs;
  bool _generating = false;
  bool _autoStarted = false;
  final List<_LocalToolEvent> _localToolEvents = [];
  final _localToolEventController = ScrollController();

  @override
  void dispose() {
    _localToolEventController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.autoGenerate && !_autoStarted) {
      _autoStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _generate2048());
    }
  }

  Future<void> _generate2048() async {
    final started = DateTime.now();
    setState(() {
      _generating = true;
      _stage = 'Starting local tool test';
      _localToolEvents.clear();
      _transcriptPath = null;
    });
    try {
      final rootDirectory = await _mobileCodeProjectsRootDirectory();
      final projectDirectory = Directory(p.join(rootDirectory.path, 'local_tool_2048'));

      await _emitLocalToolEvent(
        _LocalToolEvent(
          kind: _LocalToolEventKind.system,
          title: 'Local tool harness booted',
          detail:
              'This is a scripted local tool test, not a model-provider agent call. Loaded phone-safe tools: list_files, write_file, read_file, preview_webview, runtime_probe, github_connect.',
          time: DateTime.now(),
        ),
      );
      await _emitLocalToolEvent(
        _LocalToolEvent(
          kind: _LocalToolEventKind.thought,
          title: 'Reasoning',
          detail:
              'Goal is a real local 2048 project. The local harness will create an app-owned workspace, generate a complete single-file web app, save it atomically, read it back, then make WebView preview available.',
          time: DateTime.now(),
        ),
      );

      final listStarted = DateTime.now();
      await _emitLocalToolEvent(
        _LocalToolEvent(
          kind: _LocalToolEventKind.toolCall,
          title: 'tool_call: list_files',
          toolName: 'list_files',
          path: rootDirectory.path,
          detail: jsonEncode({
            'path': 'mobilecode_projects',
            'maxDepth': 1,
          }),
          time: DateTime.now(),
        ),
      );
      await rootDirectory.create(recursive: true);
      final existingProjects = rootDirectory
          .listSync()
          .map((entity) => entity.path.split(Platform.pathSeparator).last)
          .where((name) => name.trim().isNotEmpty)
          .take(8)
          .toList();
      await _emitLocalToolEvent(
        _LocalToolEvent(
          kind: _LocalToolEventKind.observation,
          title: 'tool_result: list_files',
          toolName: 'list_files',
          path: rootDirectory.path,
          durationMs: DateTime.now().difference(listStarted).inMilliseconds,
          detail: existingProjects.isEmpty
              ? 'No local MobileCode projects yet.'
              : 'Found: ${existingProjects.join(', ')}',
          time: DateTime.now(),
        ),
      );

      final prepareStarted = DateTime.now();
      await _emitLocalToolEvent(
        _LocalToolEvent(
          kind: _LocalToolEventKind.toolCall,
          title: 'tool_call: mkdir',
          toolName: 'write_file',
          path: projectDirectory.path,
          detail: jsonEncode({
            'path': 'mobilecode_projects/local_tool_2048',
            'recursive': true,
          }),
          time: DateTime.now(),
        ),
      );
      await projectDirectory.create(recursive: true);
      await _emitLocalToolEvent(
        _LocalToolEvent(
          kind: _LocalToolEventKind.observation,
          title: 'tool_result: mkdir',
          toolName: 'write_file',
          path: projectDirectory.path,
          durationMs: DateTime.now().difference(prepareStarted).inMilliseconds,
          detail: 'Workspace ready inside Android app documents.',
          time: DateTime.now(),
        ),
      );

      await _emitLocalToolEvent(
        _LocalToolEvent(
          kind: _LocalToolEventKind.thought,
          title: 'Plan code structure',
          detail:
              'Single index.html keeps the demo portable: responsive board, swipe/keyboard input, score, best score, undo, game-over detection, and localStorage persistence.',
          time: DateTime.now(),
        ),
      );

      final html = _localTool2048Html();
      final chunks = _chunkText(html, 1500);
      await _emitLocalToolEvent(
        _LocalToolEvent(
          kind: _LocalToolEventKind.toolCall,
          title: 'tool_call: write_file',
          toolName: 'write_file',
          path: '${projectDirectory.path}/index.html',
          detail: jsonEncode({
            'path': 'mobilecode_projects/local_tool_2048/index.html',
            'bytes': utf8.encode(html).length,
            'atomic': true,
          }),
          time: DateTime.now(),
        ),
      );
      for (var index = 0; index < chunks.length; index++) {
        await _emitLocalToolEvent(
          _LocalToolEvent(
            kind: _LocalToolEventKind.fileWrite,
            title: 'Writing code chunk ${index + 1}/${chunks.length}',
            toolName: 'write_file',
            path: '${projectDirectory.path}/index.html',
            detail: _compact(chunks[index], limit: 360),
            time: DateTime.now(),
          ),
          delay: const Duration(milliseconds: 90),
        );
      }

      final writeStarted = DateTime.now();
      final tempFile = File('${projectDirectory.path}/index.html.tmp');
      final file = File('${projectDirectory.path}/index.html');
      await tempFile.writeAsString(html, flush: true);
      if (await file.exists()) {
        await file.delete();
      }
      await tempFile.rename(file.path);
      await _emitLocalToolEvent(
        _LocalToolEvent(
          kind: _LocalToolEventKind.observation,
          title: 'tool_result: write_file',
          toolName: 'write_file',
          path: file.path,
          durationMs: DateTime.now().difference(writeStarted).inMilliseconds,
          detail: 'Wrote ${html.length} characters to index.html through temp-file rename.',
          time: DateTime.now(),
        ),
      );

      await _emitLocalToolEvent(
        _LocalToolEvent(
          kind: _LocalToolEventKind.diff,
          title: 'Generated diff',
          toolName: 'write_file',
          path: file.path,
          detail: [
            '+ mobilecode_projects/local_tool_2048/index.html',
            '+ responsive 4x4 2048 board',
            '+ swipe and keyboard controls',
            '+ score, best score, undo, game-over state',
            '+ offline WebView-ready JavaScript',
          ].join('\n'),
          time: DateTime.now(),
        ),
      );

      final readStarted = DateTime.now();
      await _emitLocalToolEvent(
        _LocalToolEvent(
          kind: _LocalToolEventKind.toolCall,
          title: 'tool_call: read_file',
          toolName: 'read_file',
          path: file.path,
          detail: jsonEncode({
            'path': 'mobilecode_projects/local_tool_2048/index.html',
            'purpose': 'verify saved file and prepare preview',
          }),
          time: DateTime.now(),
        ),
      );
      final savedHtml = await file.readAsString();
      await _emitLocalToolEvent(
        _LocalToolEvent(
          kind: _LocalToolEventKind.observation,
          title: 'tool_result: read_file',
          toolName: 'read_file',
          path: file.path,
          durationMs: DateTime.now().difference(readStarted).inMilliseconds,
          detail: 'Read back ${savedHtml.length} characters. Preview input is ready.',
          time: DateTime.now(),
        ),
      );
      if (!mounted) return;
      setState(() {
        _projectPath = file.path;
        _html = savedHtml;
        _stage = 'Generated and saved';
        _lastGenerateMs = DateTime.now().difference(started).inMilliseconds;
      });

      await _emitLocalToolEvent(
        _LocalToolEvent(
          kind: _LocalToolEventKind.preview,
          title: 'tool_call: preview_webview',
          toolName: 'preview_webview',
          path: file.path,
          detail:
              'WebView preview is armed. Tap Preview to run the generated game inside MobileCode without leaving the app.',
          durationMs: _lastGenerateMs,
          time: DateTime.now(),
        ),
      );
      await _emitLocalToolEvent(
        _LocalToolEvent(
          kind: _LocalToolEventKind.finalAnswer,
          title: 'Local test final',
          detail:
              '2048 project is complete. The generated code is visible below, stored on-device, and ready for WebView preview or GitHub publishing.',
          durationMs: _lastGenerateMs,
          time: DateTime.now(),
        ),
      );

      final transcript = await _persistRunTranscript(projectDirectory, started);
      if (!mounted) return;
      setState(() => _transcriptPath = transcript.path);
      widget.onLog('Local test generated 2048', '${file.path} - ${_lastGenerateMs}ms', Icons.grid_4x4_outlined, _mint);
    } on Object catch (error) {
      if (!mounted) return;
      await _emitLocalToolEvent(
        _LocalToolEvent(
          kind: _LocalToolEventKind.error,
          title: 'Local test failed',
          detail: _compact(error.toString(), limit: 260),
          ok: false,
          time: DateTime.now(),
        ),
        delay: Duration.zero,
      );
      setState(() => _stage = 'Generation failed');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Generate failed: $error')));
      widget.onLog('2048 generation failed', _compact(error.toString(), limit: 120), Icons.error_outline, _rose);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _emitLocalToolEvent(
    _LocalToolEvent event, {
    Duration delay = const Duration(milliseconds: 150),
  }) async {
    if (!mounted) return;
    setState(() {
      _stage = event.title;
      _localToolEvents.add(event);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_localToolEventController.hasClients) return;
      _localToolEventController.animateTo(
        _localToolEventController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
  }

  Future<File> _persistRunTranscript(Directory projectDirectory, DateTime started) async {
    final file = File('${projectDirectory.path}/local_tool_run.json');
    final payload = {
      'agent': 'MobileCode Android Local Tool Harness',
      'inspiredBy': [
        'tool-harness: model/tool/result loop',
        'workspace-scoped transcript: shell-style tool output',
        'visible tool lifecycle: persistent session events and saved artifacts',
      ],
      'startedAt': started.toIso8601String(),
      'finishedAt': DateTime.now().toIso8601String(),
      'projectPath': _projectPath,
      'tools': _localToolSpecs
          .map((tool) => {
                'name': tool.name,
                'description': tool.description,
                'surface': tool.surface,
                'risk': tool.risk,
              })
          .toList(),
      'events': _localToolEvents.map((event) => event.toJson()).toList(),
    };
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(payload), flush: true);
    return file;
  }

  void _preview() {
    final html = _html;
    if (html == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Generate the 2048 project first')));
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
      builder: (context) => _WebPreviewSheet(
        title: '2048 local preview',
        subtitle: _projectPath ?? 'Generated HTML loaded into WebView',
        html: html,
      ),
    );
  }

  Future<void> _copyCode() async {
    final html = _html;
    if (html == null) return;
    await Clipboard.setData(ClipboardData(text: html));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Generated index.html copied')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      icon: Icons.code_outlined,
      title: 'Mobile Tool Test',
      subtitle:
          'A local scripted smoke test with visible tool calls, file writes, diff, and WebView preview.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Local tool harness',
                  style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 16),
                ),
                const SizedBox(height: 10),
                _InlineStatus(
                  icon: _generating ? Icons.sync_outlined : Icons.check_circle_outline,
                  label: _lastGenerateMs == null ? _stage : '$_stage - ${_lastGenerateMs}ms',
                  color: _generating ? _amber : (_html == null ? _faint : _mint),
                ),
                const SizedBox(height: 10),
                for (final item in const [
                  '1. Think: decide the phone-safe workspace and target artifact.',
                  '2. Act: call list_files, write_file, read_file, and preview_webview.',
                  '3. Observe: show tool results, latency, generated diff, and saved paths.',
                  '4. Finish: leave code, transcript, and preview entry visible for inspection.',
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Text(item, style: const TextStyle(color: _muted, height: 1.35)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const _LocalToolRegistry(tools: _localToolSpecs),
          const SizedBox(height: 12),
          _LocalToolTranscript(
            events: _localToolEvents,
            running: _generating,
            controller: _localToolEventController,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _generating ? null : _generate2048,
                  icon: _generating
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_fix_high_outlined),
                  label: Text(_generating ? 'Running test' : 'Run local tool test'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _preview,
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Preview'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _html == null ? null : _copyCode,
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copy code'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: widget.onOpenGitHub,
                  icon: const Icon(Icons.hub_outlined),
                  label: const Text('GitHub test'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_projectPath != null || _transcriptPath != null)
            _Panel(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_projectPath != null)
                    Row(
                      children: [
                        const Icon(Icons.description_outlined, color: _mint, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _projectPath!,
                            style: const TextStyle(color: _muted, fontSize: 12, height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  if (_transcriptPath != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.receipt_long_outlined, color: _cyan, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _transcriptPath!,
                            style: const TextStyle(color: _muted, fontSize: 12, height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 12),
          _Panel(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              _html == null
                  ? 'No generated code yet. Tap "Run local tool test" to create a real local project.'
                  : _compact(_html!, limit: 2600),
              style: const TextStyle(color: _muted, fontSize: 12, height: 1.4, fontFamily: 'monospace'),
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: widget.onOpenOnlineDemo,
            icon: const Icon(Icons.public_outlined),
            label: const Text('Open already published online 2048 demo'),
          ),
        ],
      ),
    );
  }
}

class _WebPreviewSheet extends StatefulWidget {
  const _WebPreviewSheet({
    required this.title,
    required this.subtitle,
    required this.html,
  });

  final String title;
  final String subtitle;
  final String html;

  @override
  State<_WebPreviewSheet> createState() => _WebPreviewSheetState();
}

Future<bool> _launchHtmlInExternalBrowser(
  String html, {
  String browserOpenMode = _browserOpenModeSystem,
}) async {
  final dataUri = Uri.dataFromString(html, mimeType: 'text/html', encoding: utf8);
  if (await _launchUrlWithBrowserMode(dataUri, browserOpenMode)) {
    return true;
  }
  return launchUrl(dataUri, mode: LaunchMode.platformDefault);
}

Future<void> _openHtmlInBrowser(BuildContext context, String html) async {
  try {
    final opened = await _launchHtmlInExternalBrowser(html);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(opened ? 'Opened generated HTML in browser.' : 'No browser accepted this generated HTML.')),
    );
  } on Object catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_compact(error.toString(), limit: 140))));
  }
}

Future<void> _openExternalUrl(
  BuildContext context,
  String url, {
  String label = 'URL',
  String browserOpenMode = _browserOpenModeSystem,
}) async {
  try {
    final uri = Uri.parse(url);
    final opened = await _launchUrlWithBrowserMode(uri, browserOpenMode);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(opened ? 'Opened $label with ${_browserOpenModeLabel(browserOpenMode)}.' : 'Could not open $label.')),
    );
  } on Object catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_compact(error.toString(), limit: 140))));
  }
}

Future<void> _copyText(BuildContext context, String value, String label) async {
  await Clipboard.setData(ClipboardData(text: value));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label copied.')));
}

class _PagesDeploymentSummary {
  const _PagesDeploymentSummary({
    required this.url,
    required this.repositoryUrl,
    required this.artifactPath,
    required this.publishedAt,
    required this.readinessSummary,
  });

  final String url;
  final String repositoryUrl;
  final String artifactPath;
  final DateTime publishedAt;
  final String readinessSummary;
}

class _GitHubPagesArtifactDeploySheet extends StatefulWidget {
  const _GitHubPagesArtifactDeploySheet({
    required this.artifactPath,
    required this.onDeployed,
  });

  final String artifactPath;
  final Future<void> Function(_PagesDeploymentSummary summary) onDeployed;

  @override
  State<_GitHubPagesArtifactDeploySheet> createState() => _GitHubPagesArtifactDeploySheetState();
}

class _GitHubPagesArtifactDeploySheetState extends State<_GitHubPagesArtifactDeploySheet> {
  late final GitHubDeepService _github;
  late final TextEditingController _repoController;
  late final TextEditingController _descriptionController;
  final _readinessService = HtmlPublishReadinessService();
  GitHubPagesService? _pages;
  bool _loading = true;
  bool _checkingReadiness = true;
  bool _deploying = false;
  bool _privateRepo = false;
  bool _tokenValid = false;
  bool _allowRemoteAssets = false;
  bool _warningsAccepted = false;
  String? _user;
  GitHubRemoteWorkspaceLink? _remoteLink;
  String? _error;
  HtmlPublishReadinessReport? _readiness;
  DeploymentResult? _result;
  final List<String> _steps = [];

  @override
  void initState() {
    super.initState();
    _github = GitHubDeepService();
    final projectName = p.basename(p.dirname(widget.artifactPath));
    _repoController = TextEditingController(text: _sanitizeRepoName('mobilecode-$projectName'));
    _descriptionController = TextEditingController(
      text: 'Generated and deployed from MobileCode mobile AI workspace.',
    );
    unawaited(_loadRemoteLinkDefault());
    unawaited(_runReadinessCheck());
    unawaited(_initialize());
  }

  @override
  void dispose() {
    _repoController.dispose();
    _descriptionController.dispose();
    _pages?.dispose();
    _github.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _github.initialize();
      var valid = false;
      if (_github.isAuthenticated) {
        valid = await _github.validateToken();
      }
      if (!mounted) return;
      _pages ??= GitHubPagesService(_github);
      setState(() {
        _tokenValid = valid;
        _user = _github.currentUser;
        _loading = false;
        if (!valid && _github.isAuthenticated) {
          _error = 'GitHub session expired or token scope is insufficient. Please sign in again.';
        }
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _tokenValid = false;
        _error = _compact(error.toString(), limit: 160);
      });
    }
  }

  Future<void> _loadRemoteLinkDefault() async {
    final link = await GitHubRepoHubService.findRemoteLinkForPath(widget.artifactPath);
    if (!mounted || link == null) return;
    setState(() {
      _remoteLink = link;
      _repoController.text = _sanitizeRepoName(link.name);
      _descriptionController.text = 'Generated and deployed from MobileCode for ${link.fullName}.';
    });
  }

  Future<void> _runReadinessCheck() async {
    setState(() {
      _checkingReadiness = true;
      _warningsAccepted = false;
    });
    try {
      final report = await _readinessService.checkFile(
        widget.artifactPath,
        allowRemoteAssets: _allowRemoteAssets,
      );
      if (!mounted) return;
      setState(() {
        _readiness = report;
        _checkingReadiness = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _readiness = HtmlPublishReadinessReport(
          sourcePath: widget.artifactPath,
          checkedAt: DateTime.now(),
          allowRemoteAssets: _allowRemoteAssets,
          issues: [
            HtmlPublishIssue(
              code: 'check_failed',
              title: 'Pre-publish check failed',
              detail: _compact(error.toString(), limit: 180),
              severity: HtmlPublishIssueSeverity.blocking,
            ),
          ],
        );
        _checkingReadiness = false;
      });
    }
  }

  Future<void> _openGitHubLogin() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const GitHubScreen()));
    if (!mounted) return;
    await _initialize();
  }

  Future<void> _deploy() async {
    if (_deploying) return;
    final readiness = _readiness;
    if (_checkingReadiness) {
      setState(() => _error = 'Wait for the HTML pre-publish check to finish.');
      return;
    }
    if (readiness == null) {
      await _runReadinessCheck();
      if (!mounted) return;
      if (_readiness == null) {
        setState(() => _error = 'HTML pre-publish check did not complete.');
        return;
      }
    }
    if (_readiness?.blocked == true) {
      setState(() => _error = 'Fix the blocking HTML publish checks before deploying.');
      return;
    }
    if (_readiness?.hasWarnings == true && !_warningsAccepted) {
      final confirmed = await _confirmWarningPublish(_readiness!);
      if (!confirmed) return;
      _warningsAccepted = true;
    }

    final repoName = _sanitizeRepoName(_repoController.text);
    if (repoName.isEmpty) {
      setState(() => _error = 'Repository name is required.');
      return;
    }
    final signedInOwner = _github.currentUser;
    final owner = _remoteLink?.owner ?? signedInOwner;
    final pages = _pages;
    if (!_tokenValid || signedInOwner == null || owner == null || pages == null) {
      setState(() => _error = 'Please sign in to GitHub before deploying.');
      return;
    }

    final artifact = File(widget.artifactPath);
    if (!await artifact.exists()) {
      setState(() => _error = 'Generated HTML file was not found on this phone.');
      return;
    }

    final deploySteps = <String>[
      'Using GitHub account: $signedInOwner',
      'Project folder: ${p.dirname(widget.artifactPath)}',
      if (_remoteLink != null) 'Bound workspace: ${_remoteLink!.fullName}',
      'Target repo: $owner/$repoName',
    ];

    setState(() {
      _deploying = true;
      _error = null;
      _result = null;
      _steps
        ..clear()
        ..addAll(deploySteps);
    });

    try {
      var createdRepo = false;
      try {
        await _github.getRepoDetails(owner, repoName);
        _addStep('Repository exists. Reusing $owner/$repoName.');
      } on GitHubDeepException catch (error) {
        if (error.statusCode != 404) rethrow;
        if (_remoteLink != null && owner != signedInOwner) {
          setState(() {
            _deploying = false;
            _error =
                'Bound repository $owner/$repoName is not visible to this token. Reconnect GitHub with access to that owner or create the repo on GitHub first.';
          });
          return;
        }
        _addStep('Repository does not exist. Creating $owner/$repoName...');
        await _github.createRepo(
          repoName,
          description: _descriptionController.text.trim(),
          isPrivate: _privateRepo,
          autoInit: true,
        );
        createdRepo = true;
        _addStep('Repository created.');
      }

      _addStep('Uploading static HTML to gh-pages...');
      final result = await pages.deploy(
        localProjectPath: p.dirname(widget.artifactPath),
        owner: owner,
        repo: repoName,
        buildType: BuildType.staticHtml,
      );

      if (!mounted) return;
      setState(() {
        _result = result;
        _deploying = false;
        _steps
          ..addAll(result.steps)
          ..add(createdRepo ? 'New repository flow completed.' : 'Existing repository flow completed.');
        if (!result.success) {
          final lines = <String>[
            result.error ?? 'GitHub Pages deployment failed.',
            if (result.recoveryHint != null) result.recoveryHint!,
            if (result.statusCode != null) 'HTTP ${result.statusCode} - ${result.failureKind ?? 'github_api_failed'}',
          ];
          _error = lines.join('\n');
        }
      });

      if (result.success && result.url != null) {
        await widget.onDeployed(_PagesDeploymentSummary(
          url: result.url!,
          repositoryUrl: 'https://github.com/$owner/$repoName',
          artifactPath: widget.artifactPath,
          publishedAt: result.deployedAt,
          readinessSummary: (_readiness ?? readiness)?.toAgentSummary(maxIssues: 3) ?? 'HTML publish readiness: not checked',
        ));
      }
    } on Object catch (error) {
      final failure = GitHubPagesService.describeFailure(error);
      if (!mounted) return;
      setState(() {
        _deploying = false;
        _error = '${failure.message}\n${failure.recoveryHint}';
      });
    }
  }

  Future<bool> _confirmWarningPublish(HtmlPublishReadinessReport report) async {
    final warnings = report.warningIssues.take(5).toList(growable: false);
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Publish with warnings?'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('The HTML can be published, but MobileCode found quality warnings:'),
                  const SizedBox(height: 12),
                  for (final issue in warnings)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text('${issue.title}\n${issue.detail}', style: const TextStyle(fontSize: 13, height: 1.3)),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Review first')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Publish anyway')),
            ],
          ),
        ) ??
        false;
  }

  void _addStep(String step) {
    if (!mounted) return;
    setState(() => _steps.add(step));
  }

  Future<void> _openUrl(String url) async {
    await _openExternalUrl(context, url, label: 'GitHub Pages URL');
  }

  Future<void> _copy(String value, String label) async {
    await _copyText(context, value, label);
  }

  Future<void> _openArtifactCode() async {
    try {
      final file = File(widget.artifactPath);
      if (!await file.exists()) {
        setState(() => _error = 'Generated HTML file was not found on this phone.');
        return;
      }
      final code = await file.readAsString();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: _panel,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(10))),
        builder: (context) => _CodeFileSheet(
          path: widget.artifactPath,
          code: code,
          onOpenEditor: () => unawaited(_openArtifactInEditor(widget.artifactPath, initialContent: code)),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = _compact(error.toString(), limit: 160));
    }
  }

  Future<void> _openArtifactInEditor(String path, {String? initialContent}) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EditorScreen(
          initialFilePath: path,
          initialContent: initialContent,
          fileName: p.basename(path),
        ),
      ),
    );
  }

  Future<void> _openProjectFolder() async {
    try {
      final workspaceRoot = await _mobileCodeProjectsRootDirectory();
      final folder = Directory(p.dirname(widget.artifactPath));
      if (!await folder.exists()) {
        setState(() => _error = 'Project folder was not found on this phone.');
        return;
      }
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: _panel,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(10))),
        builder: (context) => _ProjectFolderSheet(
          initialPath: folder.path,
          workspaceRoot: workspaceRoot.path,
          onOpenFile: (filePath) => unawaited(_copy(filePath, 'File path')),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = _compact(error.toString(), limit: 160));
    }
  }

  @override
  Widget build(BuildContext context) {
    final projectDir = p.dirname(widget.artifactPath);
    final repoName = _sanitizeRepoName(_repoController.text);
    final owner = _remoteLink?.owner ?? _user;
    final previewUrl = owner == null || repoName.isEmpty ? null : 'https://$owner.github.io/$repoName';
    final repositoryUrl = owner == null || repoName.isEmpty ? null : 'https://github.com/$owner/$repoName';

    return _SheetScaffold(
      icon: Icons.rocket_launch_outlined,
      title: 'Deploy to GitHub Pages',
      subtitle: widget.artifactPath,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PublishReadinessPanel(
            report: _readiness,
            checking: _checkingReadiness,
            allowRemoteAssets: _allowRemoteAssets,
            onAllowRemoteAssetsChanged: (value) {
              setState(() => _allowRemoteAssets = value);
              unawaited(_runReadinessCheck());
            },
            onRefresh: () => unawaited(_runReadinessCheck()),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const _Panel(
              padding: EdgeInsets.all(18),
              child: Row(
                children: [
                  SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 10),
                  Expanded(child: Text('Checking GitHub session...', style: TextStyle(color: _muted))),
                ],
              ),
            )
          else if (!_tokenValid)
            _Panel(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.lock_outline, color: _amber, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text('GitHub login required', style: TextStyle(color: _text, fontWeight: FontWeight.w900)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Sign in once with a GitHub token that can create repositories, write contents, and configure Pages. Fine-grained tokens need Repository contents read/write, Pages read/write, and Administration read/write. Classic PATs need the repo scope.',
                    style: TextStyle(color: _muted, fontSize: 12, height: 1.35),
                  ),
                  const SizedBox(height: 12),
                  _RuntimeActionButton(
                    icon: Icons.login_outlined,
                    label: 'Open GitHub login',
                    disabled: false,
                    onTap: () => unawaited(_openGitHubLogin()),
                  ),
                ],
              ),
            )
          else ...[
            _Panel(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.verified_outlined, color: _mint, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Ready as ${owner ?? 'GitHub user'}',
                          style: const TextStyle(color: _text, fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _repoController,
                    enabled: !_deploying,
                    decoration: const InputDecoration(
                      labelText: 'Repository name',
                      prefixIcon: Icon(Icons.source_outlined),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _descriptionController,
                    enabled: !_deploying,
                    minLines: 1,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Repository description',
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    value: _privateRepo,
                    onChanged: _deploying ? null : (value) => setState(() => _privateRepo = value),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Private repository', style: TextStyle(color: _text, fontSize: 13, fontWeight: FontWeight.w800)),
                    subtitle: const Text(
                      'Public is recommended for Pages demos. Private Pages may depend on your GitHub plan.',
                      style: TextStyle(color: _muted, fontSize: 11, height: 1.25),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _DeployPreviewLine(label: 'Local folder', value: projectDir),
                  if (repositoryUrl != null) _DeployPreviewLine(label: 'Repository', value: repositoryUrl),
                  if (previewUrl != null) _DeployPreviewLine(label: 'Pages URL', value: previewUrl),
                  if (_remoteLink != null) _DeployPreviewLine(label: 'Bound repo', value: _remoteLink!.fullName),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _deploying || _checkingReadiness || (_readiness?.blocked ?? false) ? null : _deploy,
                      icon: _deploying
                          ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.rocket_launch_outlined),
                      label: Text(_deploying ? 'Deploying...' : 'One-click deploy'),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_steps.isNotEmpty) ...[
            const SizedBox(height: 12),
            _Panel(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Deployment log', style: TextStyle(color: _text, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  for (final step in _steps.take(14))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.check_circle_outline, color: _mint, size: 14),
                          const SizedBox(width: 6),
                          Expanded(child: Text(step, style: const TextStyle(color: _muted, fontSize: 11, height: 1.25))),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            _Panel(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline, color: _rose, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: const TextStyle(color: _rose, fontSize: 12, height: 1.35))),
                ],
              ),
            ),
          ],
          if (_result?.success == true && _result?.url != null) ...[
            const SizedBox(height: 12),
            _PublishedWorkCard(
              info: _PublishedArtifactInfo(
                pagesUrl: _result!.url!,
                repositoryUrl: repositoryUrl ?? '',
                artifactPath: widget.artifactPath,
                publishedAt: _result!.deployedAt,
                readinessSummary: _readiness?.toAgentSummary(maxIssues: 3),
              ),
              onOpenPages: () => unawaited(_openUrl(_result!.url!)),
              onOpenRepo: repositoryUrl == null ? null : () => unawaited(_openUrl(repositoryUrl)),
              onOpenCode: () => unawaited(_openArtifactCode()),
              onRedeploy: _deploying ? null : () => unawaited(_deploy()),
              onCopyPath: () => unawaited(_copy(widget.artifactPath, 'Phone file path')),
              onOpenFolder: () => unawaited(_openProjectFolder()),
            ),
          ],
        ],
      ),
    );
  }
}

class _DeployPreviewLine extends StatelessWidget {
  const _DeployPreviewLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 86,
            child: Text(label, style: const TextStyle(color: _faint, fontSize: 11)),
          ),
          Expanded(
            child: SelectableText(
              value,
              maxLines: 2,
              style: const TextStyle(color: _muted, fontSize: 11, height: 1.25),
            ),
          ),
        ],
      ),
    );
  }
}

class _PublishReadinessPanel extends StatelessWidget {
  const _PublishReadinessPanel({
    required this.report,
    required this.checking,
    required this.allowRemoteAssets,
    required this.onAllowRemoteAssetsChanged,
    required this.onRefresh,
  });

  final HtmlPublishReadinessReport? report;
  final bool checking;
  final bool allowRemoteAssets;
  final ValueChanged<bool> onAllowRemoteAssetsChanged;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final status = checking ? 'Checking' : (report?.statusLabel ?? 'Not checked');
    final blocked = report?.blocked ?? false;
    final warnings = report?.hasWarnings ?? false;
    final color = checking
        ? _cyan
        : blocked
            ? _rose
            : warnings
                ? _amber
                : _mint;
    final icon = checking
        ? Icons.sync_outlined
        : blocked
            ? Icons.block_outlined
            : warnings
                ? Icons.warning_amber_outlined
                : Icons.verified_outlined;
    final issues = report?.issues.take(5).toList(growable: false) ?? const <HtmlPublishIssue>[];

    return _Panel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Pre-publish check - $status',
                  style: const TextStyle(color: _text, fontWeight: FontWeight.w900),
                ),
              ),
              TextButton.icon(
                onPressed: checking ? null : onRefresh,
                icon: const Icon(Icons.refresh_outlined, size: 16),
                label: const Text('Recheck'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            checking
                ? 'Checking title, viewport, private paths, external assets, mobile touch targets, and basic accessibility.'
                : report == null
                    ? 'Run the readiness check before publishing.'
                    : '${report!.blockingIssues.length} blockers, ${report!.warningIssues.length} warnings. Blockers must be fixed before GitHub Pages deploy.',
            style: const TextStyle(color: _muted, fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: allowRemoteAssets,
            onChanged: checking ? null : onAllowRemoteAssetsChanged,
            title: const Text('Allow remote assets', style: TextStyle(color: _text, fontSize: 12, fontWeight: FontWeight.w800)),
            subtitle: const Text(
              'Keep this off for fully self-contained HTML. Turn on only when external links/CDNs are intentional.',
              style: TextStyle(color: _muted, fontSize: 11, height: 1.25),
            ),
          ),
          if (issues.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final issue in issues)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      issue.severity == HtmlPublishIssueSeverity.blocking ? Icons.error_outline : Icons.info_outline,
                      color: issue.severity == HtmlPublishIssueSeverity.blocking ? _rose : _amber,
                      size: 15,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(issue.title, style: const TextStyle(color: _text, fontSize: 12, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          Text(issue.detail, style: const TextStyle(color: _muted, fontSize: 11, height: 1.25)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            if ((report?.issues.length ?? 0) > issues.length)
              Text('${report!.issues.length - issues.length} more checks hidden.', style: const TextStyle(color: _faint, fontSize: 11)),
          ],
        ],
      ),
    );
  }
}

class _PublishedWorkCard extends StatelessWidget {
  const _PublishedWorkCard({
    required this.info,
    required this.onOpenPages,
    required this.onOpenRepo,
    required this.onOpenCode,
    required this.onRedeploy,
    required this.onCopyPath,
    required this.onOpenFolder,
  });

  final _PublishedArtifactInfo info;
  final VoidCallback onOpenPages;
  final VoidCallback? onOpenRepo;
  final VoidCallback? onOpenCode;
  final VoidCallback? onRedeploy;
  final VoidCallback onCopyPath;
  final VoidCallback onOpenFolder;

  @override
  Widget build(BuildContext context) {
    final shareText = [
      'MobileCode published web page',
      info.pagesUrl,
      if (info.repositoryUrl.isNotEmpty) info.repositoryUrl,
    ].join('\n');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _mint.withOpacity(0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _mint.withOpacity(0.10),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _mint.withOpacity(0.22)),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: _panel,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _mint.withOpacity(0.24)),
                  ),
                  child: const Icon(Icons.public_outlined, color: _mint, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('作品已发布', style: const TextStyle(color: _text, fontSize: 15, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 3),
                      Text(
                        '${info.title} - ${_timeLabel(info.publishedAt)}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _muted, fontSize: 12, height: 1.3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _PublishedPagesThumbnail(url: info.pagesUrl),
          const SizedBox(height: 10),
          _PublishedLinkLine(label: 'Pages', value: info.pagesUrl, color: _blue),
          if (info.repositoryUrl.isNotEmpty) _PublishedLinkLine(label: 'Repo', value: info.repositoryUrl, color: _violet),
          _PublishedLinkLine(label: 'File', value: info.artifactPath, color: _muted),
          if (info.readinessSummary != null && info.readinessSummary!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(info.readinessSummary!, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _faint, fontSize: 11, height: 1.3)),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MiniArtifactButton(icon: Icons.open_in_browser_outlined, label: '打开网页', onTap: onOpenPages, color: _blue),
              if (onOpenRepo != null)
                _MiniArtifactButton(
                  icon: Icons.code_outlined,
                  leading: const _GitHubMarkIcon(size: 15, color: _violet),
                  label: '打开仓库',
                  onTap: onOpenRepo!,
                  color: _violet,
                ),
              if (onOpenCode != null) _MiniArtifactButton(icon: Icons.description_outlined, label: '代码文件', onTap: onOpenCode!, color: _mint),
              if (onRedeploy != null) _MiniArtifactButton(icon: Icons.rocket_launch_outlined, label: '重新发布', onTap: onRedeploy!, color: _amber),
              _MiniArtifactButton(icon: Icons.folder_open_outlined, label: '工程文件夹', onTap: onOpenFolder, color: _mint),
              _MiniArtifactButton(
                icon: Icons.ios_share_outlined,
                label: '复制分享',
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: info.pagesUrl));
                  await Share.share(shareText, subject: 'MobileCode published page');
                },
                color: _cyan,
              ),
              _MiniArtifactButton(icon: Icons.folder_copy_outlined, label: '复制路径', onTap: onCopyPath, color: _faint),
            ],
          ),
        ],
      ),
    );
  }
}

class _PublishedPagesThumbnail extends StatefulWidget {
  const _PublishedPagesThumbnail({required this.url});

  final String url;

  @override
  State<_PublishedPagesThumbnail> createState() => _PublishedPagesThumbnailState();
}

class _PublishedPagesThumbnailState extends State<_PublishedPagesThumbnail> {
  late final WebViewController _controller;
  int _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(_panel)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onWebResourceError: (error) {
            if (mounted) {
              setState(() => _error = _compact(error.description, limit: 90));
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 138,
        decoration: BoxDecoration(
          color: _panelSoft,
          border: Border.all(color: _line),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Transform.scale(
                scale: 0.72,
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: MediaQuery.of(context).size.width / 0.72,
                  height: 190,
                  child: IgnorePointer(child: WebViewWidget(controller: _controller)),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: AnimatedOpacity(
                opacity: _progress < 100 ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: LinearProgressIndicator(value: _progress / 100),
              ),
            ),
            if (_error != null)
              Positioned.fill(
                child: Container(
                  color: _panelSoft,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.image_not_supported_outlined, color: _amber),
                      const SizedBox(height: 6),
                      Text(
                        'Live Pages thumbnail unavailable: $_error',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: _muted, fontSize: 11, height: 1.25),
                      ),
                    ],
                  ),
                ),
              ),
            Positioned(
              left: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _text.withOpacity(0.72),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('GitHub Pages live preview', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PublishedLinkLine extends StatelessWidget {
  const _PublishedLinkLine({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 44, child: Text(label, style: const TextStyle(color: _faint, fontSize: 11, fontWeight: FontWeight.w800))),
          Expanded(
            child: SelectableText(
              value,
              maxLines: 2,
              style: TextStyle(color: color, fontSize: 11, height: 1.25),
            ),
          ),
        ],
      ),
    );
  }
}

String _sanitizeRepoName(String value) {
  final normalized = value
      .trim()
      .replaceAll(RegExp(r'\s+'), '-')
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'-{2,}'), '-')
      .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
  if (normalized.isEmpty) return 'mobilecode-site';
  return normalized.length <= 80 ? normalized : normalized.substring(0, 80);
}

class _WebPreviewSheetState extends State<_WebPreviewSheet> {
  late final WebViewController _controller;
  int _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(_bg)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onWebResourceError: (error) {
            if (mounted) {
              setState(() => _error = '${error.errorCode}: ${error.description}');
            }
          },
        ),
      )
      ..loadHtmlString(widget.html);
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      icon: Icons.preview_outlined,
      title: widget.title,
      subtitle: widget.subtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Panel(
            padding: EdgeInsets.zero,
            child: Stack(
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.72,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: WebViewWidget(controller: _controller),
                  ),
                ),
                if (_progress < 100)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: LinearProgressIndicator(value: _progress / 100),
                  ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            _Panel(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline, color: _rose, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_error!, style: const TextStyle(color: _rose, fontSize: 12, height: 1.35)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _RuntimeActionButton(
                icon: Icons.open_in_browser_outlined,
                label: '浏览器打开',
                disabled: false,
                onTap: () => unawaited(_openHtmlInBrowser(context, widget.html)),
              ),
              _RuntimeActionButton(
                icon: Icons.copy_outlined,
                label: 'Copy HTML',
                disabled: false,
                onTap: () {
                  Clipboard.setData(ClipboardData(text: widget.html));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Generated HTML copied.')));
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Preview mode runs generated HTML inside the app through Android WebView. Browser open uses a generated data URL because Android app-private files are not directly readable by other apps.',
            style: TextStyle(color: _muted, fontSize: 12, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _CodeFileSheet extends StatefulWidget {
  const _CodeFileSheet({
    required this.path,
    required this.code,
    required this.onOpenEditor,
  });

  final String path;
  final String code;
  final VoidCallback onOpenEditor;

  @override
  State<_CodeFileSheet> createState() => _CodeFileSheetState();
}

class _CodeFileSheetState extends State<_CodeFileSheet> {
  static const _previewLineCount = 110;

  final _codeScrollController = ScrollController();
  bool _expanded = false;

  @override
  void dispose() {
    _codeScrollController.dispose();
    super.dispose();
  }

  List<String> get _lines => widget.code.split('\n');

  Map<String, int> _htmlSections(List<String> lines) {
    final markers = <String, RegExp>{
      'head': RegExp(r'<head\b', caseSensitive: false),
      'style': RegExp(r'<style\b', caseSensitive: false),
      'body': RegExp(r'<body\b', caseSensitive: false),
      'script': RegExp(r'<script\b', caseSensitive: false),
    };
    final sections = <String, int>{};
    for (final entry in markers.entries) {
      for (var i = 0; i < lines.length; i++) {
        if (entry.value.hasMatch(lines[i])) {
          sections[entry.key] = i;
          break;
        }
      }
    }
    return sections;
  }

  void _jumpToLine(int line) {
    setState(() => _expanded = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_codeScrollController.hasClients) return;
      final offset = ((line - 2).clamp(0, line) * 15.8).toDouble();
      _codeScrollController.animateTo(
        offset.clamp(0.0, _codeScrollController.position.maxScrollExtent).toDouble(),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final lines = _lines;
    final isHtml = _isWebArtifactPath(widget.path) || widget.code.trimLeft().toLowerCase().startsWith('<!doctype html') || widget.code.toLowerCase().contains('<html');
    final visibleLines = _expanded ? lines : lines.take(_previewLineCount).toList();
    final hiddenLines = lines.length - visibleLines.length;
    final sections = isHtml ? _htmlSections(lines) : const <String, int>{};
    final maxCodeHeight = MediaQuery.of(context).size.height * 0.52;
    return _SheetScaffold(
      icon: Icons.code_outlined,
      title: 'Generated Code',
      subtitle: widget.path,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _RuntimeActionButton(
                icon: Icons.edit_note_outlined,
                label: '用编辑器打开',
                disabled: false,
                onTap: () {
                  final openEditor = widget.onOpenEditor;
                  Navigator.of(context).pop();
                  WidgetsBinding.instance.addPostFrameCallback((_) => openEditor());
                },
              ),
              _RuntimeActionButton(
                icon: Icons.copy_outlined,
                label: 'Copy code',
                disabled: false,
                onTap: () {
                  Clipboard.setData(ClipboardData(text: widget.code));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Generated code copied.')));
                },
              ),
              _RuntimeActionButton(
                icon: Icons.folder_copy_outlined,
                label: 'Copy path',
                disabled: false,
                onTap: () {
                  Clipboard.setData(ClipboardData(text: widget.path));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Phone file path copied.')));
                },
              ),
              _RuntimeActionButton(
                icon: _expanded ? Icons.unfold_less_outlined : Icons.unfold_more_outlined,
                label: _expanded ? 'Collapse' : 'Expand all',
                disabled: lines.length <= _previewLineCount,
                onTap: () {
                  setState(() => _expanded = !_expanded);
                  if (!_expanded && _codeScrollController.hasClients) {
                    _codeScrollController.jumpTo(0);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          _Panel(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  widget.path,
                  style: const TextStyle(color: _muted, fontSize: 12, height: 1.35),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _TaskDetailChip(label: '${lines.length} lines', color: _cyan),
                    _TaskDetailChip(label: _formatBytes(utf8.encode(widget.code).length), color: _violet),
                    if (!_expanded && hiddenLines > 0) _TaskDetailChip(label: '$hiddenLines hidden', color: _amber),
                  ],
                ),
              ],
            ),
          ),
          if (sections.isNotEmpty) ...[
            const SizedBox(height: 12),
            _Panel(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('HTML quick jump', style: TextStyle(color: _text, fontSize: 12, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final entry in sections.entries)
                        _CodeSectionChip(
                          label: entry.key,
                          line: entry.value + 1,
                          onTap: () => _jumpToLine(entry.value),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          _Panel(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_expanded ? Icons.subject_outlined : Icons.short_text_outlined, color: _mint, size: 17),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _expanded ? 'Full file' : 'Preview first $_previewLineCount lines',
                        style: const TextStyle(color: _text, fontSize: 12, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxCodeHeight.clamp(260.0, 560.0).toDouble()),
                  child: Scrollbar(
                    controller: _codeScrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _codeScrollController,
                      padding: const EdgeInsets.only(right: 8),
                      child: SelectableText(
                        visibleLines.join('\n'),
                        style: const TextStyle(
                          color: _text,
                          fontFamily: 'monospace',
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
                ),
                if (hiddenLines > 0) ...[
                  const SizedBox(height: 10),
                  Text(
                    '$hiddenLines more lines are folded to keep this sheet readable.',
                    style: const TextStyle(color: _amber, fontSize: 11, height: 1.3),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CodeSectionChip extends StatelessWidget {
  const _CodeSectionChip({
    required this.label,
    required this.line,
    required this.onTap,
  });

  final String label;
  final int line;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: const Icon(Icons.tag_outlined, color: _cyan, size: 15),
      label: Text('$label · L$line'),
      side: BorderSide(color: _cyan.withOpacity(0.35)),
      backgroundColor: _cyan.withOpacity(0.08),
      labelStyle: const TextStyle(color: _text, fontSize: 12, fontWeight: FontWeight.w800),
      onPressed: onTap,
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb >= 100 ? 0 : 1)} KB';
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
}

class _QuickActionGrid extends StatelessWidget {
  const _QuickActionGrid({required this.onAction});

  final ValueChanged<_ModuleAction> onAction;

  @override
  Widget build(BuildContext context) {
    final actions = const [
      _QuickAction(Icons.forum_outlined, 'AI Chat', _ModuleAction.aiChat, _mint),
      _QuickAction(Icons.hub_outlined, 'GitHub', _ModuleAction.githubTest, _cyan),
      _QuickAction(Icons.handyman_outlined, 'Tools', _ModuleAction.toolLab, _amber),
      _QuickAction(Icons.terminal_outlined, 'Runtime', _ModuleAction.termuxCheck, _lime),
      _QuickAction(Icons.psychology_alt_outlined, 'Deep Dive', _ModuleAction.deepDive, _violet),
      _QuickAction(Icons.rocket_launch_outlined, 'Build', _ModuleAction.build, _amber),
      _QuickAction(Icons.note_add_outlined, 'New File', _ModuleAction.newFile, _cyan),
      _QuickAction(Icons.edit_note_outlined, 'Diary', _ModuleAction.diary, _blue),
      _QuickAction(Icons.health_and_safety_outlined, 'Guard', _ModuleAction.healthCheck, _rose),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 680 ? 4 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: actions.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            childAspectRatio: columns == 2 ? 2.65 : 2.2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemBuilder: (context, index) {
            final action = actions[index];
            return _QuickActionTile(action: action, onTap: () => onAction(action.action));
          },
        );
      },
    );
  }
}

class _QuickAction {
  const _QuickAction(this.icon, this.label, this.action, this.color);

  final IconData icon;
  final String label;
  final _ModuleAction action;
  final Color color;
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({required this.action, required this.onTap});

  final _QuickAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _panel,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _line),
          ),
          child: Row(
            children: [
              Icon(action.icon, color: action.color, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  action.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _text, fontWeight: FontWeight.w700),
                ),
              ),
              const Icon(Icons.chevron_right_outlined, color: _faint, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(color: _text, fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(color: _muted, fontSize: 12, height: 1.35),
        ),
      ],
    );
  }
}

class _LayerSelector extends StatelessWidget {
  const _LayerSelector({
    required this.layers,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<_CapabilityLayer> layers;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: layers.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final layer = layers[index];
          final selected = index == selectedIndex;
          return Tooltip(
            message: layer.subtitle,
            child: ChoiceChip(
              selected: selected,
              onSelected: (_) => onSelected(index),
              avatar: Icon(layer.icon, size: 18, color: selected ? _bg : layer.color),
              label: Text(layer.name),
              labelStyle: TextStyle(
                color: selected ? _bg : _text,
                fontWeight: FontWeight.w700,
              ),
              selectedColor: layer.color,
              backgroundColor: _panel,
              side: BorderSide(color: selected ? layer.color : _line),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          );
        },
      ),
    );
  }
}

class _LayerHeader extends StatelessWidget {
  const _LayerHeader({required this.layer});

  final _CapabilityLayer layer;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _panelSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: layer.color, width: 4)),
      ),
      child: Row(
        children: [
          Icon(layer.icon, color: layer.color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  layer.name,
                  style: const TextStyle(color: _text, fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  layer.subtitle,
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ),
          ),
          _Pill(
            label: '${layer.serviceCount} services',
            icon: Icons.storage_outlined,
            color: layer.color,
          ),
        ],
      ),
    );
  }
}

class _CapabilityCard extends StatelessWidget {
  const _CapabilityCard({
    required this.capability,
    required this.layerColor,
    required this.onRun,
    required this.onInspect,
  });

  final _Capability capability;
  final Color layerColor;
  final VoidCallback onRun;
  final VoidCallback onInspect;

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(capability.status);
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: layerColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: layerColor.withOpacity(0.4)),
                ),
                child: Icon(capability.icon, color: layerColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      capability.title,
                      style: const TextStyle(color: _text, fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      capability.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _muted, fontSize: 12, height: 1.35),
                    ),
                  ],
                ),
              ),
              _StatusPill(status: capability.status, color: statusColor),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final service in capability.services.take(3))
                _MiniChip(label: service, color: layerColor),
              if (capability.services.length > 3)
                _MiniChip(label: '+${capability.services.length - 3}', color: _faint),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onRun,
                  icon: const Icon(Icons.play_arrow_outlined),
                  label: const Text('Open'),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.outlined(
                tooltip: 'Inspect services',
                onPressed: onInspect,
                icon: const Icon(Icons.manage_search_outlined),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OperationsBoard extends StatelessWidget {
  const _OperationsBoard({
    required this.activity,
    required this.drafts,
    required this.snippets,
    required this.healthState,
    required this.layerCount,
    required this.serviceCount,
  });

  final List<_ActivityLog> activity;
  final List<_DraftFile> drafts;
  final List<_SnippetDraft> snippets;
  final _HealthState healthState;
  final int layerCount;
  final int serviceCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          title: 'Operations Board',
          subtitle: 'The working surface keeps local drafts, snippets, health, and recent module actions visible.',
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 680 ? 4 : 2;
            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: columns,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.85,
              children: [
                _MetricCard(label: 'Layers', value: '$layerCount', icon: Icons.account_tree_outlined, color: _mint),
                _MetricCard(label: 'Services', value: '$serviceCount', icon: Icons.storage_outlined, color: _cyan),
                _MetricCard(label: 'Drafts', value: '${drafts.length}', icon: Icons.note_add_outlined, color: _amber),
                _MetricCard(label: 'Snippets', value: '${snippets.length}', icon: Icons.data_object_outlined, color: _lime),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.history_outlined, color: _mint),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Recent Activity',
                      style: TextStyle(color: _text, fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                  ),
                  _StatusPill(status: _healthToStatus(healthState), color: _healthColor(healthState)),
                ],
              ),
              const SizedBox(height: 12),
              for (final item in activity.take(6)) _ActivityRow(item: item),
            ],
          ),
        ),
        if (drafts.isNotEmpty || snippets.isNotEmpty) ...[
          const SizedBox(height: 12),
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Local Work Items',
                  style: TextStyle(color: _text, fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 10),
                for (final draft in drafts.take(3))
                  _WorkItemRow(icon: Icons.description_outlined, title: draft.name, detail: draft.language, color: _cyan),
                for (final snippet in snippets.take(3))
                  _WorkItemRow(icon: Icons.data_object_outlined, title: snippet.title, detail: snippet.language, color: _lime),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const Spacer(),
          Text(value, style: const TextStyle(color: _text, fontSize: 22, fontWeight: FontWeight.w800)),
          Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.item});

  final _ActivityLog item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(item.icon, color: item.color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: const TextStyle(color: _text, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  item.detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(_timeLabel(item.time), style: const TextStyle(color: _faint, fontSize: 11)),
        ],
      ),
    );
  }
}

class _WorkItemRow extends StatelessWidget {
  const _WorkItemRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _text, fontWeight: FontWeight.w700),
            ),
          ),
          Text(detail, style: const TextStyle(color: _muted, fontSize: 12)),
        ],
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.tab, required this.onChanged});

  final _HomeTab tab;
  final ValueChanged<_HomeTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = switch (tab) {
      _HomeTab.control => 0,
      _HomeTab.ai => 0,
      _HomeTab.ship => 1,
      _HomeTab.guard => 2,
      _HomeTab.insight => 2,
    };
    return Container(
      decoration: const BoxDecoration(
        color: _panel,
        border: Border(top: BorderSide(color: _line)),
      ),
      child: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) => onChanged(switch (index) {
          0 => _HomeTab.control,
          1 => _HomeTab.ship,
          _ => _HomeTab.guard,
        }),
        backgroundColor: _panel,
        indicatorColor: _mint.withOpacity(0.16),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.forum_outlined), selectedIcon: Icon(Icons.forum), label: 'Chat'),
          NavigationDestination(icon: Icon(Icons.handyman_outlined), selectedIcon: Icon(Icons.handyman), label: 'Tools'),
          NavigationDestination(icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune), label: 'Settings'),
        ],
      ),
    );
  }
}

class _GitHubTestSheet extends StatefulWidget {
  const _GitHubTestSheet({
    required this.onOpenWeb,
    required this.onLog,
  });

  final VoidCallback onOpenWeb;
  final void Function(String title, String detail, IconData icon, Color color) onLog;

  @override
  State<_GitHubTestSheet> createState() => _GitHubTestSheetState();
}

class _GitHubTestSheetState extends State<_GitHubTestSheet> {
  final _token = TextEditingController();
  final _repo = TextEditingController(text: 'Harzva/mobilecode');
  bool _testing = false;
  final List<String> _lines = ['Not tested yet.'];

  @override
  void dispose() {
    _token.dispose();
    _repo.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _testing = true;
      _lines
        ..clear()
        ..add('Testing GitHub...');
    });
    final token = _token.text.trim();
    final repo = _repo.text.trim().isEmpty ? 'Harzva/mobilecode' : _repo.text.trim();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final user = await _get(client, 'https://api.github.com/user', token);
      final repoRes = await _get(client, 'https://api.github.com/repos/$repo', token);
      final pages = await _get(client, 'https://api.github.com/repos/$repo/pages', token);
      if (!mounted) return;
      setState(() {
        _lines
          ..clear()
          ..add('${user.statusCode == 200 ? 'OK' : 'FAIL'} /user HTTP ${user.statusCode}')
          ..add('${repoRes.statusCode == 200 ? 'OK' : 'FAIL'} repo HTTP ${repoRes.statusCode}')
          ..add('${pages.statusCode == 200 ? 'OK' : 'WARN'} pages HTTP ${pages.statusCode}');
        if (user.body.contains('"login"')) _lines.add('Identity response received.');
        if (repoRes.statusCode != 200) _lines.add('Repo test failed: missing token scope or repo access.');
        if (pages.statusCode == 403) _lines.add('Pages permission missing: fine-grained tokens need Pages write + Administration write; classic PATs need repo.');
        if (pages.statusCode == 404) _lines.add('Pages not enabled yet, repo is private/invisible, or token cannot read Pages settings.');
        if (pages.statusCode == 422) _lines.add('GitHub rejected the Pages settings. Check repo name, branch, and visibility.');
      });
      widget.onLog(
        repoRes.statusCode == 200 ? 'GitHub connected' : 'GitHub test failed',
        'repo HTTP ${repoRes.statusCode}',
        repoRes.statusCode == 200 ? Icons.hub_outlined : Icons.error_outline,
        repoRes.statusCode == 200 ? _mint : _rose,
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _lines
          ..clear()
          ..add('Network error: ${_compact(error.toString(), limit: 180)}');
      });
      widget.onLog('GitHub network error', _compact(error.toString(), limit: 120), Icons.error_outline, _rose);
    } finally {
      client.close(force: true);
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<({int statusCode, String body})> _get(HttpClient client, String url, String token) async {
    final request = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 10));
    request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    request.headers.set('X-GitHub-Api-Version', '2022-11-28');
    if (token.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    final response = await request.close().timeout(const Duration(seconds: 20));
    final body = await utf8.decodeStream(response);
    return (statusCode: response.statusCode, body: body);
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      icon: Icons.hub_outlined,
      title: 'GitHub Connectivity',
      subtitle: 'Test token identity, repository access, and Pages readiness.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _token,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'GitHub token', prefixIcon: Icon(Icons.key_outlined)),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _repo,
            decoration: const InputDecoration(labelText: 'Owner/repo', prefixIcon: Icon(Icons.account_tree_outlined)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _testing ? null : _run,
                  icon: _testing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.network_check_outlined),
                  label: Text(_testing ? 'Testing' : 'Test in APK'),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.outlined(
                tooltip: 'Open web test page',
                onPressed: widget.onOpenWeb,
                icon: const Icon(Icons.open_in_browser_outlined),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in _lines) _GitHubConnectivityLine(line: line),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GitHubConnectivityLine extends StatelessWidget {
  const _GitHubConnectivityLine({required this.line});

  final String line;

  @override
  Widget build(BuildContext context) {
    final color = _githubConnectivityColor(line);
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 9,
            height: 9,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              line,
              style: TextStyle(color: color == _faint ? _muted : color, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

Color _githubConnectivityColor(String line) {
  final lower = line.toLowerCase();
  if (lower.startsWith('ok') || lower.contains('identity response')) return _mint;
  if (lower.startsWith('fail') || lower.startsWith('network error') || lower.contains('failed')) return _rose;
  if (lower.startsWith('warn') || lower.contains('permission missing') || lower.contains('not enabled') || lower.contains('rejected')) return _amber;
  return _faint;
}

class _LarkCliDiagnosticsSheet extends StatefulWidget {
  const _LarkCliDiagnosticsSheet({
    required this.runtimeManager,
    required this.onOpenDocs,
    required this.onLog,
  });

  final RuntimeManager runtimeManager;
  final VoidCallback onOpenDocs;
  final void Function(String title, String detail, IconData icon, Color color) onLog;

  @override
  State<_LarkCliDiagnosticsSheet> createState() => _LarkCliDiagnosticsSheetState();
}

class _LarkCliDiagnosticsSheetState extends State<_LarkCliDiagnosticsSheet> {
  final _query = TextEditingController(text: 'MobileCode');
  final _title = TextEditingController(text: 'MobileCode draft');
  final _content = TextEditingController(text: 'Generated from MobileCode. Review before publishing.');
  final _target = TextEditingController();
  String _selectedAction = 'docs_search';
  bool _checking = false;
  bool _runningAction = false;
  final List<String> _lines = [
    'Lark CLI connector is opt-in. MobileCode only runs fixed diagnostic commands through RuntimeProvider.',
    'Install official larksuite/cli, then run config init and auth login --recommend in your runtime.',
  ];

  @override
  void dispose() {
    _query.dispose();
    _title.dispose();
    _content.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _runDiagnostics() async {
    setState(() {
      _checking = true;
      _lines
        ..clear()
        ..add('Checking active RuntimeProvider...');
    });

    try {
      await widget.runtimeManager.initialize();
      final capabilities = await widget.runtimeManager.capabilities();
      if (!capabilities.shell) {
        _finish(false, 'Active runtime has no shell capability. Start MobileCode Helper or External Termux before using lark-cli.');
        return;
      }

      final version = await widget.runtimeManager.execute(
        'lark-cli --version || lark --version',
        timeout: const Duration(seconds: 10),
      );
      if (!version.success) {
        _finish(
          false,
          'lark-cli is not available in the active runtime.\nInstall: https://github.com/larksuite/cli\nThen run: lark-cli config init && lark-cli auth login --recommend',
        );
        return;
      }

      final auth = await widget.runtimeManager.execute(
        'lark-cli auth status --output json || lark-cli auth status || lark auth status --output json || lark auth status',
        timeout: const Duration(seconds: 12),
      );
      final authOutput = (auth.stdout.trim().isNotEmpty ? auth.stdout : auth.stderr).trim();
      _finish(
        auth.success,
        [
          'lark-cli detected: ${(version.stdout.trim().isEmpty ? version.stderr : version.stdout).trim()}',
          if (authOutput.isNotEmpty) 'auth status: ${_compact(authOutput, limit: 320)}' else 'auth status returned no output.',
          'Next structured actions will stay opt-in: docs search, task creation, wiki draft, and dry-run message compose.',
        ].join('\n'),
      );
    } on Object catch (error) {
      _finish(false, _compact(error.toString(), limit: 360));
    }
  }

  void _finish(bool ok, String message) {
    if (!mounted) return;
    setState(() {
      _checking = false;
      _lines
        ..clear()
        ..add(message);
    });
    widget.onLog(
      ok ? 'Lark CLI ready' : 'Lark CLI needs setup',
      _compact(message, limit: 120),
      ok ? Icons.business_center_outlined : Icons.info_outline,
      ok ? _mint : _amber,
    );
  }

  Future<void> _runStructuredAction() async {
    final command = _buildStructuredCommand();
    if (command == null) {
      setState(() {
        _lines
          ..clear()
          ..add('Fill the required fields before running this structured action.');
      });
      return;
    }

    setState(() {
      _runningAction = true;
      _lines
        ..clear()
        ..add('Running structured Lark action:')
        ..add(command);
    });

    try {
      final result = await widget.runtimeManager.execute(command, timeout: const Duration(seconds: 30));
      final output = (result.stdout.trim().isNotEmpty ? result.stdout : result.stderr).trim();
      if (!mounted) return;
      setState(() {
        _runningAction = false;
        _lines
          ..clear()
          ..add(result.success ? 'Structured action completed.' : 'Structured action failed.')
          ..add('Command: $command')
          ..add(output.isEmpty ? 'No output returned.' : _compact(output, limit: 1200));
      });
      widget.onLog(
        result.success ? 'Lark action completed' : 'Lark action failed',
        _compact(output.isEmpty ? command : output, limit: 120),
        result.success ? Icons.business_center_outlined : Icons.error_outline,
        result.success ? _mint : _rose,
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _runningAction = false;
        _lines
          ..clear()
          ..add('Structured action failed.')
          ..add(_compact(error.toString(), limit: 800));
      });
    }
  }

  String? _buildStructuredCommand() {
    final title = _title.text.trim();
    final content = _content.text.trim();
    final query = _query.text.trim();
    final target = _target.text.trim();
    return switch (_selectedAction) {
      'docs_search' when query.isNotEmpty =>
        'lark-cli docs +search --query ${_quoteCommandArg(query)} --format json || lark-cli drive +search --query ${_quoteCommandArg(query)} --format json',
      'task_create' when title.isNotEmpty =>
        'lark-cli task +create --title ${_quoteCommandArg(title)} --notes ${_quoteCommandArg(content)} --dry-run --format json',
      'wiki_draft' when title.isNotEmpty && content.isNotEmpty =>
        'lark-cli docs +create --api-version v2 --doc-format markdown --title ${_quoteCommandArg(title)} --content ${_quoteCommandArg('# $title\n\n$content')} --dry-run --format json',
      'message_dry_run' when target.isNotEmpty && content.isNotEmpty =>
        'lark-cli im +messages-send --chat-id ${_quoteCommandArg(target)} --text ${_quoteCommandArg(content)} --dry-run --format json',
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      icon: Icons.business_center_outlined,
      title: 'Lark CLI Connector',
      subtitle: 'Opt-in first-party connector: diagnostics and auth guidance only in v1.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Panel(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('Controlled connector boundary', style: TextStyle(color: _text, fontWeight: FontWeight.w900)),
                SizedBox(height: 8),
                Text(
                  'MobileCode does not expose arbitrary Lark shell execution. This connector first checks the official CLI, auth status, and missing setup. Write actions will stay structured and confirm-before-send.',
                  style: TextStyle(color: _muted, fontSize: 12, height: 1.35),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _RuntimeActionButton(
                icon: Icons.health_and_safety_outlined,
                label: _checking ? 'Checking' : 'Run diagnostics',
                disabled: _checking,
                onTap: _runDiagnostics,
              ),
              _RuntimeActionButton(
                icon: Icons.open_in_browser_outlined,
                label: 'Official CLI',
                disabled: false,
                onTap: widget.onOpenDocs,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _Panel(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Structured actions', style: TextStyle(color: _text, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                const Text(
                  'These are fixed Lark CLI flows. Task, wiki, and message actions default to --dry-run so the user can review before any write.',
                  style: TextStyle(color: _muted, fontSize: 12, height: 1.35),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _selectedAction,
                  decoration: const InputDecoration(labelText: 'Action', prefixIcon: Icon(Icons.route_outlined)),
                  items: const [
                    DropdownMenuItem(value: 'docs_search', child: Text('Document search')),
                    DropdownMenuItem(value: 'task_create', child: Text('Create task dry-run')),
                    DropdownMenuItem(value: 'wiki_draft', child: Text('Wiki/doc draft dry-run')),
                    DropdownMenuItem(value: 'message_dry_run', child: Text('Message dry-run')),
                  ],
                  onChanged: _runningAction ? null : (value) => setState(() => _selectedAction = value ?? 'docs_search'),
                ),
                const SizedBox(height: 10),
                if (_selectedAction == 'docs_search')
                  TextField(
                    controller: _query,
                    enabled: !_runningAction,
                    decoration: const InputDecoration(labelText: 'Search query', prefixIcon: Icon(Icons.search_outlined)),
                  )
                else ...[
                  TextField(
                    controller: _title,
                    enabled: !_runningAction,
                    decoration: const InputDecoration(labelText: 'Title', prefixIcon: Icon(Icons.title_outlined)),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _content,
                    enabled: !_runningAction,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(labelText: 'Content', alignLabelWithHint: true, prefixIcon: Icon(Icons.notes_outlined)),
                  ),
                  if (_selectedAction == 'message_dry_run') ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _target,
                      enabled: !_runningAction,
                      decoration: const InputDecoration(labelText: 'Chat ID', prefixIcon: Icon(Icons.alternate_email_outlined)),
                    ),
                  ],
                ],
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _runningAction ? null : _runStructuredAction,
                    icon: _runningAction
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.play_arrow_outlined),
                    label: Text(_runningAction ? 'Running action' : 'Run structured action'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Panel(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              _lines.join('\n\n'),
              style: const TextStyle(color: _muted, fontSize: 12, height: 1.4),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Setup commands inside the active runtime: lark-cli config init, then lark-cli auth login --recommend. MobileCode will show missing scopes before any future write action.',
            style: TextStyle(color: _faint, fontSize: 11, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _DiarySheet extends StatefulWidget {
  const _DiarySheet({required this.onLog});

  final void Function(String title, String detail, IconData icon, Color color) onLog;

  @override
  State<_DiarySheet> createState() => _DiarySheetState();
}

class _DiarySheetState extends State<_DiarySheet> {
  static const _key = 'mobilecode.diary.entries';
  final _title = TextEditingController();
  final _body = TextEditingController();
  final List<_DiaryEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return;
    final decoded = jsonDecode(raw);
    if (decoded is List && mounted) {
      setState(() {
        _entries
          ..clear()
          ..addAll(decoded.whereType<Map>().map((item) => _DiaryEntry.fromJson(Map<String, dynamic>.from(item))));
      });
    }
  }

  Future<void> _save() async {
    final title = _title.text.trim().isEmpty ? 'Daily note' : _title.text.trim();
    final body = _body.text.trim();
    if (body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Write diary content first')));
      return;
    }
    setState(() {
      _entries.insert(0, _DiaryEntry(title: title, body: body, time: DateTime.now()));
      _title.clear();
      _body.clear();
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_entries.map((entry) => entry.toJson()).toList()));
    widget.onLog('Diary entry saved', title, Icons.edit_note_outlined, _amber);
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      icon: Icons.edit_note_outlined,
      title: 'Diary APK Demo',
      subtitle: 'A tiny local app inside MobileCode. It proves forms, storage, list rendering, and APK runtime.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title', prefixIcon: Icon(Icons.title_outlined)),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _body,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(labelText: 'Today I...', alignLabelWithHint: true),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save diary entry'),
            ),
          ),
          const SizedBox(height: 16),
          Text('Entries (${_entries.length})', style: const TextStyle(color: _text, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          if (_entries.isEmpty)
            const Text('No entries yet.', style: TextStyle(color: _muted))
          else
            for (final entry in _entries.take(5))
              _Panel(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.title, style: const TextStyle(color: _text, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(_timeLabel(entry.time), style: const TextStyle(color: _faint, fontSize: 11)),
                    const SizedBox(height: 6),
                    Text(entry.body, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, height: 1.35)),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _ToolLabSheet extends StatefulWidget {
  const _ToolLabSheet({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.onOpen2048,
    required this.onOpenGitHubWeb,
    required this.onLog,
  });

  final String baseUrl;
  final String apiKey;
  final String model;
  final VoidCallback onOpen2048;
  final VoidCallback onOpenGitHubWeb;
  final void Function(String title, String detail, IconData icon, Color color) onLog;

  @override
  State<_ToolLabSheet> createState() => _ToolLabSheetState();
}

class _ToolLabSheetState extends State<_ToolLabSheet> {
  final List<_ToolProbeResult> _results = [];
  bool _running = false;

  static const _tools = [
    _ToolProbe(name: 'Provider tool list', detail: 'Shows Agent Loop function tools and preset permissions.', icon: Icons.schema_outlined, action: 'tool_list'),
    _ToolProbe(name: 'AI provider health', detail: 'Uses configured Base URL and model.', icon: Icons.monitor_heart_outlined, action: 'health'),
    _ToolProbe(name: 'GitHub web tester', detail: 'Opens a Pages test page for token and repo checks.', icon: Icons.hub_outlined, action: 'github_web'),
    _ToolProbe(name: 'Code 2048 project', detail: 'Runs the local coding lab and WebView preview flow.', icon: Icons.grid_4x4_outlined, action: 'demo_2048'),
    _ToolProbe(name: 'Local storage', detail: 'Writes and reads SharedPreferences.', icon: Icons.save_outlined, action: 'storage'),
    _ToolProbe(name: 'Runtime providers', detail: 'Checks MobileCode Helper and External Termux fallback.', icon: Icons.terminal_outlined, action: 'runtime'),
    _ToolProbe(name: 'Root permission', detail: 'Detects whether a su binary is visible for backend keepalive.', icon: Icons.admin_panel_settings_outlined, action: 'root'),
  ];

  Future<void> _runAll() async {
    setState(() {
      _running = true;
      _results.clear();
    });
    await _run('storage');
    await _run('runtime');
    await _run('root');
    await _run('health');
    if (mounted) setState(() => _running = false);
  }

  Future<void> _run(String action) async {
    if (action == 'tool_list') {
      final toolNames = _providerNativeToolSpecs.map((tool) => tool.name).join(', ');
      final presets = AgentPreset.values.map((preset) => '${preset.label}: ${preset.allowedToolNames.length}').join(' / ');
      _addResult(
        'Provider tool list',
        true,
        'Agent Loop exposes $toolNames. Presets: $presets. Blocked by design: shell, Git push, publishing, remote logs, arbitrary commands.',
      );
      return;
    }
    if (action == 'github_web') {
      widget.onOpenGitHubWeb();
      _addResult('GitHub web tester', true, 'Opened external browser page.');
      return;
    }
    if (action == 'demo_2048') {
      widget.onOpen2048();
      _addResult('Code 2048 project', true, 'Opened Mobile Coding Lab.');
      return;
    }
    if (action == 'storage') {
      final prefs = await SharedPreferences.getInstance();
      final stamp = DateTime.now().toIso8601String();
      await prefs.setString('mobilecode.tool.storageProbe', stamp);
      final ok = prefs.getString('mobilecode.tool.storageProbe') == stamp;
      _addResult('Local storage', ok, ok ? 'Write/read succeeded.' : 'Readback mismatch.');
      return;
    }
    if (action == 'runtime') {
      final helper = await _probeHelperDaemon();
      final installed = await _isAndroidPackageInstalled('com.termux');
      final apiInstalled = await _isAndroidPackageInstalled('com.termux.api');
      if (helper.ready) {
        _addResult('Runtime providers', true, helper.detail);
      } else if (installed == true) {
        final termuxDetail = apiInstalled == true ? 'External Termux + External Termux:API fallback detected.' : 'External Termux fallback detected; External Termux:API not detected.';
        _addResult('Runtime providers', true, '${helper.detail} $termuxDetail');
      } else if (installed == false) {
        _addResult('Runtime providers', false, '${helper.detail} External Termux is not installed or not visible.');
      } else {
        final urlVisible = await canLaunchUrl(Uri.parse('termux://'));
        _addResult(
          'Runtime providers',
          urlVisible,
          urlVisible
              ? '${helper.detail} termux:// handler is visible; package channel unavailable.'
              : '${helper.detail} No Helper daemon and package channel is unavailable.',
        );
      }
      return;
    }
    if (action == 'root') {
      final probe = await _probeRootAvailability();
      if (probe == null) {
        _addResult('Root permission', false, 'Root probe channel is unavailable in this build.');
      } else {
        _addResult('Root permission', probe.available, probe.detail);
      }
      return;
    }
    if (action == 'health') {
      if (widget.baseUrl.isEmpty) {
        _addResult('AI provider health', false, 'Base URL is empty.');
        return;
      }
      final flavor = _detectApiFlavor(widget.baseUrl, widget.model);
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      try {
        final uri = flavor == _ApiFlavor.anthropic ? _anthropicMessagesUri(widget.baseUrl) : _openAiChatUri(widget.baseUrl);
        _parseBaseUrl(widget.baseUrl);
        final request = flavor == _ApiFlavor.anthropic
            ? await client.postUrl(uri).timeout(const Duration(seconds: 8))
            : await client.getUrl(Uri.parse('${_normalizedBaseUrl(widget.baseUrl)}/models')).timeout(const Duration(seconds: 8));
        if (widget.apiKey.isNotEmpty) {
          request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${widget.apiKey}');
          if (flavor == _ApiFlavor.anthropic) request.headers.set('x-api-key', widget.apiKey);
        }
        if (flavor == _ApiFlavor.anthropic) {
          request.headers.contentType = ContentType.json;
          request.headers.set('anthropic-version', '2023-06-01');
          request.write(jsonEncode({
            'model': widget.model.isEmpty ? 'claude-3-5-haiku-latest' : widget.model,
            'max_tokens': 1,
            'messages': [
              {'role': 'user', 'content': 'ping'},
            ],
          }));
        }
        final response = await request.close().timeout(const Duration(seconds: 30));
        await response.drain();
        _addResult('AI provider health', response.statusCode >= 200 && response.statusCode < 300, 'HTTP ${response.statusCode} via ${_flavorLabel(flavor)}');
      } on Object catch (error) {
        _addResult('AI provider health', false, _compact(error.toString(), limit: 120));
      } finally {
        client.close(force: true);
      }
    }
  }

  Future<_HelperDaemonProbeResult> _probeHelperDaemon() async {
    final first = await _probeHelperDaemonOnce();
    if (first.ready) return first;

    final started = await _startMobileCodeHelperService();
    if (started != true) return first;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final second = await _probeHelperDaemonOnce();
    if (second.ready) return second;
    return _HelperDaemonProbeResult(
      ready: false,
      detail: '${first.detail} Native Helper service start was requested, but localhost is still not ready.',
    );
  }

  Future<_HelperDaemonProbeResult> _probeHelperDaemonOnce() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final uri = Uri.parse('http://127.0.0.1:8765/v1/health');
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 2));
      final response = await request.close().timeout(const Duration(seconds: 3));
      final body = await utf8.decodeStream(response);
      final decoded = jsonDecode(body);
      final name = decoded is Map ? decoded['name'] as String? ?? 'MobileCode Helper' : 'MobileCode Helper';
      final status = decoded is Map ? decoded['status'] as String? ?? 'responded' : 'responded';
      final ready = response.statusCode >= 200 && response.statusCode < 300 && decoded is Map && decoded['ready'] == true;
      return _HelperDaemonProbeResult(
        ready: ready,
        detail: ready ? '$name daemon ready: $status.' : '$name daemon responded but is not ready: $status.',
      );
    } on Object catch (error) {
      return _HelperDaemonProbeResult(
        ready: false,
        detail: 'MobileCode Helper daemon not reachable on 127.0.0.1:8765 (${_compact(error.toString(), limit: 80)}).',
      );
    } finally {
      client.close(force: true);
    }
  }

  void _addResult(String name, bool ok, String message) {
    if (!mounted) return;
    setState(() {
      _results.insert(0, _ToolProbeResult(name: name, ok: ok, message: message));
    });
    widget.onLog(ok ? '$name OK' : '$name failed', message, ok ? Icons.check_circle_outline : Icons.error_outline, ok ? _mint : _rose);
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      icon: Icons.handyman_outlined,
      title: 'Mobile Tool Tests',
      subtitle: 'Run small probes for phone-optimized tools and see what fails.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Panel(
            padding: const EdgeInsets.all(12),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tool capability map', style: TextStyle(color: _text, fontWeight: FontWeight.w900)),
                SizedBox(height: 8),
                _ToolScopeLine(icon: Icons.phone_android_outlined, color: _mint, title: 'Direct Android/Flutter', detail: 'storage, network, WebView preview, clipboard, sensors, camera, microphone, notifications, secure storage, GitHub HTTP APIs'),
                _ToolScopeLine(icon: Icons.terminal_outlined, color: _amber, title: 'Needs runtime', detail: 'Helper daemon, External Termux fallback, git/ssh binaries, npm/python package managers, local build scripts, long-running command sessions'),
                _ToolScopeLine(icon: Icons.cloud_outlined, color: _cyan, title: 'Better remote', detail: 'heavy builds, concurrent agent runs, private repo automation, CI release signing, team sync'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const _LocalToolRegistry(
            tools: _providerNativeToolSpecs,
            title: 'Provider-native tool list',
            subtitle: 'These are the only tools a provider-native Agent Loop may ask MobileCode to execute. The app still validates schema, paths, URLs, and evidence before every action.',
            icon: Icons.schema_outlined,
            color: _violet,
          ),
          const SizedBox(height: 12),
          const _AndroidCommandMapPanel(),
          const SizedBox(height: 12),
          const _AgentPresetToolMatrix(),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _running ? null : _runAll,
              icon: _running
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_arrow_outlined),
              label: Text(_running ? 'Running probes' : 'Run core probes'),
            ),
          ),
          const SizedBox(height: 12),
          for (final tool in _tools)
            _Panel(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(tool.icon, color: _cyan),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tool.name, style: const TextStyle(color: _text, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(tool.detail, style: const TextStyle(color: _muted, fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton.outlined(
                    onPressed: _running ? null : () => _run(tool.action),
                    icon: const Icon(Icons.play_arrow_outlined),
                  ),
                ],
              ),
            ),
          if (_results.isNotEmpty) ...[
            const SizedBox(height: 12),
            _Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Results', style: TextStyle(color: _text, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  for (final result in _results)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(result.ok ? Icons.check_circle_outline : Icons.error_outline, color: result.ok ? _mint : _rose, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text('${result.name}: ${result.message}', style: const TextStyle(color: _muted, height: 1.35)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ToolScopeLine extends StatelessWidget {
  const _ToolScopeLine({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(color: _muted, fontSize: 12, height: 1.35),
                children: [
                  TextSpan(text: '$title: ', style: TextStyle(color: color, fontWeight: FontWeight.w900)),
                  TextSpan(text: detail),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RuntimeDiagnosticsSheet extends StatefulWidget {
  const _RuntimeDiagnosticsSheet({
    required this.runtimeManager,
    required this.initialHealth,
    required this.initialCapabilities,
    required this.termuxInstalled,
    required this.termuxApiInstalled,
    required this.rootAvailable,
    required this.onOpenInstall,
    required this.onRefreshParent,
    required this.onLog,
  });

  final RuntimeManager runtimeManager;
  final List<RuntimeHealth> initialHealth;
  final RuntimeCapabilities initialCapabilities;
  final bool? termuxInstalled;
  final bool? termuxApiInstalled;
  final bool? rootAvailable;
  final VoidCallback onOpenInstall;
  final Future<void> Function() onRefreshParent;
  final void Function(String title, String detail, IconData icon, Color color) onLog;

  @override
  State<_RuntimeDiagnosticsSheet> createState() => _RuntimeDiagnosticsSheetState();
}

class _RuntimeDiagnosticsSheetState extends State<_RuntimeDiagnosticsSheet> {
  bool _checking = false;
  late List<RuntimeHealth> _health;
  late RuntimeCapabilities _capabilities;
  bool? _termuxInstalled;
  bool? _termuxApiInstalled;
  bool? _rootAvailable;
  RuntimeTaskSnapshot? _task;
  String _status = 'Runtime diagnostics are ready to refresh.';

  @override
  void initState() {
    super.initState();
    _health = widget.initialHealth;
    _capabilities = widget.initialCapabilities;
    _termuxInstalled = widget.termuxInstalled;
    _termuxApiInstalled = widget.termuxApiInstalled;
    _rootAvailable = widget.rootAvailable;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refresh());
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _checking = true;
      _status = 'Checking Helper, External Termux, root, and active task state...';
    });
    try {
      await _startMobileCodeHelperService();
      await widget.runtimeManager.initialize();
      final health = await widget.runtimeManager.refresh();
      final capabilities = await widget.runtimeManager.capabilities();
      final termux = await _isAndroidPackageInstalled('com.termux');
      final termuxApi = await _isAndroidPackageInstalled('com.termux.api');
      final rootProbe = await _probeRootAvailability();
      final task = await widget.runtimeManager.currentTaskSnapshot();
      if (!mounted) return;
      final active = widget.runtimeManager.activeHealth;
      setState(() {
        _health = health;
        _capabilities = capabilities;
        _termuxInstalled = termux;
        _termuxApiInstalled = termuxApi;
        _rootAvailable = rootProbe?.available;
        _task = task;
        _status = '${active?.name ?? 'No runtime'}: ${active?.status ?? 'No provider responded.'}';
      });
      widget.onLog(
        active?.ready == true ? 'Runtime diagnostics ready' : 'Runtime diagnostics need setup',
        _status,
        active?.ready == true ? Icons.verified_outlined : Icons.warning_amber_outlined,
        active?.ready == true ? _mint : _amber,
      );
      unawaited(widget.onRefreshParent());
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _status = _compact(error.toString(), limit: 180);
      });
      widget.onLog('Runtime diagnostics failed', _status, Icons.error_outline, _rose);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _launchTermux() async {
    final opened = await _launchAndroidPackage('com.termux');
    if (!mounted) return;
    final message = opened
        ? 'External Termux launch intent sent.'
        : 'Could not launch com.termux. It may be missing, disabled, or hidden.';
    setState(() => _status = message);
    widget.onLog(
      opened ? 'External Termux launched' : 'External Termux launch failed',
      message,
      opened ? Icons.open_in_new_outlined : Icons.error_outline,
      opened ? _mint : _rose,
    );
  }

  Future<void> _stopTask(String taskId) async {
    setState(() {
      _checking = true;
      _status = 'Stopping runtime task $taskId...';
    });
    try {
      await widget.runtimeManager.stopTask(taskId);
      final task = await widget.runtimeManager.currentTaskSnapshot();
      if (!mounted) return;
      setState(() {
        _task = task;
        _status = task == null ? 'No active runtime task after stop request.' : 'Task ${task.taskId} is ${task.status.name}.';
      });
      widget.onLog('Runtime task stop requested', _status, Icons.stop_circle_outlined, _amber);
      unawaited(widget.onRefreshParent());
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _status = _compact(error.toString(), limit: 180));
      widget.onLog('Runtime task stop failed', _status, Icons.error_outline, _rose);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.runtimeManager.activeHealth ?? (_health.isNotEmpty ? _health.first : null);
    final healthItems = [..._health]
      ..sort((a, b) {
        int rank(RuntimeHealth item) {
          if (item.ready) return 0;
          if (item.available) return 1;
          if (item.type == RuntimeProviderType.embeddedLite || item.type == RuntimeProviderType.cloud) return 3;
          return 2;
        }

        return rank(a).compareTo(rank(b));
      });
    return _SheetScaffold(
      icon: Icons.monitor_heart_outlined,
      title: 'Runtime Diagnostics',
      subtitle: 'Helper, External Termux fallback, task recovery, and capability status in one place.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(active?.name ?? 'Runtime discovery pending', style: const TextStyle(color: _text, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(_status, style: const TextStyle(color: _muted, height: 1.4)),
                const SizedBox(height: 8),
                Text('Capabilities: ${_runtimeCapabilitiesText(_capabilities)}', style: const TextStyle(color: _faint, fontSize: 12, height: 1.35)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _checking ? null : _refresh,
                  icon: _checking
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh_outlined),
                  label: Text(_checking ? 'Refreshing' : 'Refresh'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _launchTermux,
                  icon: const Icon(Icons.open_in_new_outlined),
                  label: const Text('Open External Termux'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (healthItems.isEmpty)
            const Text('No runtime health records yet.', style: TextStyle(color: _muted))
          else
            for (final health in healthItems) ...[
              _RuntimeHealthTile(health: health),
              const SizedBox(height: 8),
            ],
          _Panel(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Fallback visibility', style: TextStyle(color: _text, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                _DiagnosticLine(label: 'External Termux', value: _boolStatus(_termuxInstalled), good: _termuxInstalled == true),
                _DiagnosticLine(label: 'External Termux:API (optional)', value: _boolStatus(_termuxApiInstalled), good: true),
                _DiagnosticLine(label: 'Root keepalive', value: _boolStatus(_rootAvailable), good: _rootAvailable == true),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _TaskSnapshotPanel(
            task: _task,
            onStop: _task?.canCancel == true && !_checking ? () => _stopTask(_task!.taskId) : null,
            onOpenDetails: _task == null
                ? null
                : () => _showRuntimeTaskDetailsSheet(
                      context: context,
                      runtimeManager: widget.runtimeManager,
                      task: _task!,
                      onLog: widget.onLog,
                    ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: widget.onOpenInstall,
            icon: const Icon(Icons.download_outlined),
            label: const Text('External Termux install guide'),
          ),
          const SizedBox(height: 12),
          const Text(
            'External Termux remains a fallback. MobileCode should prefer Helper, Embedded Lite, or Cloud providers through RuntimeManager whenever possible.',
            style: TextStyle(color: _muted, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _RuntimeActionsSheet extends StatefulWidget {
  const _RuntimeActionsSheet({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.runtimeManager,
    required this.defaultPackageManager,
    required this.onLog,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final RuntimeManager runtimeManager;
  final String defaultPackageManager;
  final void Function(String title, String detail, IconData icon, Color color) onLog;

  @override
  State<_RuntimeActionsSheet> createState() => _RuntimeActionsSheetState();
}

class _RuntimeActionsSheetState extends State<_RuntimeActionsSheet> {
  final _projectPath = TextEditingController(text: '/data/data/com.mobilecode.mobile_agent/files/mobilecode_runtime');
  final _message = TextEditingController(text: 'mobile runtime update');
  final List<String> _lines = ['No runtime action has run yet.'];
  bool _running = false;
  bool _cancelling = false;
  late String _packageManager;
  RuntimeActionType? _lastFailedAction;
  RuntimeProjectProfile? _lastProjectProfile;
  RuntimeTaskSnapshot? _lastTask;

  @override
  void initState() {
    super.initState();
    _packageManager = widget.defaultPackageManager;
  }

  @override
  void dispose() {
    _projectPath.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _run(RuntimeActionType type) async {
    final projectPath = _projectPath.text.trim();
    if (projectPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Project path is required')));
      return;
    }
    setState(() {
      _running = true;
      _lines.insert(0, 'Running ${type.name}...');
    });
    try {
      final result = await widget.runtimeManager.runAction(_requestFor(type, projectPath));
      if (!mounted) return;
      final tail = result.lastResult;
      final detail = [
        result.summary,
        if (result.skippedReason != null) result.skippedReason!,
        if (result.recoveryHint != null) 'Recovery: ${result.recoveryHint!}',
        if (tail != null && tail.stdout.trim().isNotEmpty) _compact(tail.stdout.trim(), limit: 160),
        if (tail != null && tail.stderr.trim().isNotEmpty) _compact(tail.stderr.trim(), limit: 160),
      ].join('\n');
      setState(() {
        _lastFailedAction = result.success ? null : result.action;
        _lines.insert(0, '${result.success ? 'OK' : 'FAILED'} ${type.name}: $detail');
      });
      widget.onLog(
        result.success ? 'Runtime action completed' : 'Runtime action failed',
        '${type.name}: ${result.summary}',
        result.success ? Icons.check_circle_outline : Icons.error_outline,
        result.success ? _mint : _rose,
      );
    } on Object catch (error) {
      if (!mounted) return;
      final message = _compact(error.toString(), limit: 180);
      setState(() {
        _lastFailedAction = type;
        _lines.insert(0, 'ERROR ${type.name}: $message');
      });
      widget.onLog('Runtime action error', message, Icons.error_outline, _rose);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  RuntimeActionRequest _requestFor(RuntimeActionType type, String projectPath) {
    return RuntimeActionRequest(
      type: type,
      projectPath: projectPath,
      packageManager: _selectedPackageManager,
      message: _message.text.trim(),
    );
  }

  String? get _selectedPackageManager => _packageManager == 'auto' ? null : _packageManager;

  Future<void> _preflightProject() async {
    final projectPath = _projectPath.text.trim();
    if (projectPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Project path is required')));
      return;
    }
    setState(() {
      _running = true;
      _lines.insert(0, 'Running project preflight...');
    });
    try {
      final profile = await widget.runtimeManager.preflightProject(
        projectPath,
        packageManager: _selectedPackageManager,
      );
      if (!mounted) return;
      setState(() {
        _lastProjectProfile = profile;
        _lines.insert(
          0,
          [
            'PREFLIGHT: ${profile.summary}',
            if (profile.recoveryHint != null) 'Recovery: ${profile.recoveryHint!}',
          ].join('\n'),
        );
      });
      widget.onLog(
        profile.recognized ? 'Runtime project detected' : 'Runtime project needs setup',
        profile.summary,
        profile.recognized ? Icons.search_outlined : Icons.warning_amber_outlined,
        profile.recognized ? _mint : _amber,
      );
    } on Object catch (error) {
      if (!mounted) return;
      final message = _compact(error.toString(), limit: 180);
      setState(() => _lines.insert(0, 'PREFLIGHT ERROR: $message'));
      widget.onLog('Runtime project preflight error', message, Icons.error_outline, _rose);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _runValidationLoop() async {
    final projectPath = _projectPath.text.trim();
    if (projectPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Project path is required')));
      return;
    }
    setState(() {
      _running = true;
      _lines.insert(0, 'Running validate loop...');
    });
    try {
      final result = await widget.runtimeManager.validateProject(
        projectPath: projectPath,
        packageManager: _selectedPackageManager,
        message: _message.text.trim(),
      );
      if (!mounted) return;
      final failed = result.failedStep;
      final stepLines = result.steps.map((step) => '${step.success ? 'OK' : 'FAILED'} ${step.action.name}: ${step.summary}');
      setState(() {
        _lastProjectProfile = result.profile;
        _lastFailedAction = failed?.action;
        _lines.insert(
          0,
          [
            result.success ? 'VALIDATED: ${result.summary}' : 'VALIDATION STOPPED: ${result.summary}',
            ...stepLines,
            if (result.recoveryHint != null) 'Recovery: ${result.recoveryHint!}',
          ].join('\n'),
        );
      });
      widget.onLog(
        result.success ? 'Runtime validate loop completed' : 'Runtime validate loop stopped',
        result.summary,
        result.success ? Icons.verified_outlined : Icons.error_outline,
        result.success ? _mint : _rose,
      );
    } on Object catch (error) {
      if (!mounted) return;
      final message = _compact(error.toString(), limit: 180);
      setState(() => _lines.insert(0, 'VALIDATION ERROR: $message'));
      widget.onLog('Runtime validate loop error', message, Icons.error_outline, _rose);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _retryLastFailure() async {
    final failedAction = _lastFailedAction;
    if (failedAction == null) {
      setState(() => _lines.insert(0, 'No failed runtime action to retry.'));
      return;
    }
    await widget.runtimeManager.refresh();
    await _run(failedAction);
  }

  Future<void> _cancelTask([String? taskId]) async {
    final id = taskId ?? (_lastTask?.canCancel == true ? _lastTask!.taskId : null);
    setState(() {
      _cancelling = true;
      _lines.insert(0, id == null ? 'Stopping active runtime task...' : 'Stopping runtime task $id...');
    });
    try {
      if (id == null) {
        await widget.runtimeManager.stopCurrentTask();
      } else {
        await widget.runtimeManager.stopTask(id);
      }
      final task = await widget.runtimeManager.currentTaskSnapshot();
      if (!mounted) return;
      final summary = task == null ? 'No recoverable runtime task after stop request.' : _taskSummary(task);
      setState(() {
        _lastTask = task;
        _lines.insert(0, 'STOP REQUESTED: $summary');
      });
      widget.onLog('Runtime task stop requested', summary, Icons.stop_circle_outlined, _amber);
    } on Object catch (error) {
      if (!mounted) return;
      final message = _compact(error.toString(), limit: 180);
      setState(() => _lines.insert(0, 'STOP ERROR: $message'));
      widget.onLog('Runtime task stop failed', message, Icons.error_outline, _rose);
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  Future<void> _inspectTask() async {
    setState(() => _running = true);
    try {
      final task = await widget.runtimeManager.currentTaskSnapshot();
      if (!mounted) return;
      setState(() {
        _lastTask = task;
        _lines.insert(0, task == null ? 'No recoverable runtime task.' : _taskSummary(task));
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _lines.insert(0, 'Task recovery failed: ${_compact(error.toString(), limit: 160)}'));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _useLastTaskPath() async {
    setState(() => _running = true);
    try {
      final tasks = await widget.runtimeManager.taskHistory(limit: 5);
      final task = tasks.firstWhere(
        (item) => (item.workingDir ?? '').isNotEmpty,
        orElse: () => const RuntimeTaskSnapshot(
          taskId: '',
          status: RuntimeTaskStatus.unknown,
          command: '',
          providerType: RuntimeProviderType.webViewOnly,
        ),
      );
      final path = task.workingDir;
      if (!mounted) return;
      setState(() {
        if (path == null || path.isEmpty) {
          _lines.insert(0, 'No recent runtime task with a project path.');
        } else {
          _projectPath.text = path;
          _lines.insert(0, 'Project path set from ${task.taskId}: $path');
        }
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _lines.insert(0, 'Project path recovery failed: ${_compact(error.toString(), limit: 160)}'));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _inspectHistory() async {
    setState(() => _running = true);
    try {
      final tasks = await widget.runtimeManager.taskHistory(limit: 5);
      if (!mounted) return;
      RuntimeTaskSnapshot? selectedTask;
      for (final task in tasks) {
        if (task.running) {
          selectedTask = task;
          break;
        }
      }
      selectedTask ??= tasks.isEmpty ? null : tasks.first;
      setState(() {
        _lastTask = selectedTask;
        _lines.insert(
          0,
          tasks.isEmpty
              ? 'No recoverable runtime task history.'
              : tasks.map((task) => _taskSummary(task)).join('\n\n'),
        );
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _lines.insert(0, 'Task history failed: ${_compact(error.toString(), limit: 160)}'));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _openTaskDetails() async {
    var task = _lastTask;
    if (task == null) {
      setState(() => _running = true);
      try {
        final tasks = await widget.runtimeManager.taskHistory(limit: 12);
        if (!mounted) return;
        for (final item in tasks) {
          if (item.running) {
            task = item;
            break;
          }
        }
        task ??= tasks.isEmpty ? null : tasks.first;
        final selectedTask = task;
        setState(() {
          _lastTask = selectedTask;
          _lines.insert(0, selectedTask == null ? 'No runtime task available for detail view.' : 'Opening details for ${selectedTask.taskId}.');
        });
      } on Object catch (error) {
        if (!mounted) return;
        final message = _compact(error.toString(), limit: 160);
        setState(() => _lines.insert(0, 'Task detail load failed: $message'));
        return;
      } finally {
        if (mounted) setState(() => _running = false);
      }
    }
    if (!mounted) return;
    if (task == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No runtime task to inspect.')));
      return;
    }
    _showRuntimeTaskDetailsSheet(
      context: context,
      runtimeManager: widget.runtimeManager,
      task: task,
      onLog: widget.onLog,
    );
  }

  String _taskSummary(RuntimeTaskSnapshot task) {
    final logs = _recentLogLines(task.logs, limit: 4).join('\n');
    final failure = task.failureKind == RuntimeTaskFailureKind.none ? '' : ' (${task.failureKind.name})';
    return 'Task ${task.taskId} is ${task.status.name}$failure: ${task.command}${logs.isEmpty ? '' : '\n$logs'}';
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      icon: widget.icon,
      title: widget.title,
      subtitle: widget.subtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _projectPath,
            decoration: const InputDecoration(labelText: 'Runtime project path', prefixIcon: Icon(Icons.folder_outlined)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _RuntimeActionButton(
                icon: Icons.home_work_outlined,
                label: 'Default path',
                disabled: _running,
                onTap: () {
                  _projectPath.text = '/data/data/com.mobilecode.mobile_agent/files/mobilecode_runtime';
                  setState(() => _lines.insert(0, 'Project path reset to helper workspace default.'));
                },
              ),
              _RuntimeActionButton(
                icon: Icons.restore_outlined,
                label: 'Last cwd',
                disabled: _running,
                onTap: _useLastTaskPath,
              ),
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _packageManager,
            decoration: const InputDecoration(labelText: 'Action profile', prefixIcon: Icon(Icons.tune_outlined)),
            items: const [
              DropdownMenuItem(value: 'auto', child: Text('Auto from capabilities')),
              DropdownMenuItem(value: 'flutter', child: Text('Flutter')),
              DropdownMenuItem(value: 'npm', child: Text('Node / npm')),
              DropdownMenuItem(value: 'python', child: Text('Python')),
            ],
            onChanged: _running ? null : (value) => setState(() => _packageManager = value ?? 'auto'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _message,
            decoration: const InputDecoration(labelText: 'Commit message', prefixIcon: Icon(Icons.edit_note_outlined)),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _RuntimeActionButton(icon: Icons.inventory_2_outlined, label: 'Install', disabled: _running, onTap: () => _run(RuntimeActionType.installDependencies)),
              _RuntimeActionButton(icon: Icons.fact_check_outlined, label: 'Test', disabled: _running, onTap: () => _run(RuntimeActionType.runTests)),
              _RuntimeActionButton(icon: Icons.web_asset_outlined, label: 'Preview', disabled: _running, onTap: () => _run(RuntimeActionType.buildPreview)),
              _RuntimeActionButton(icon: Icons.search_outlined, label: 'Preflight', disabled: _running, onTap: _preflightProject),
              _RuntimeActionButton(icon: Icons.verified_outlined, label: 'Validate', disabled: _running, onTap: _runValidationLoop),
              _RuntimeActionButton(icon: Icons.stop_circle_outlined, label: 'Stop', disabled: _cancelling, onTap: _cancelTask),
              _RuntimeActionButton(icon: Icons.replay_outlined, label: 'Retry', disabled: _running || _lastFailedAction == null, onTap: _retryLastFailure),
              _RuntimeActionButton(icon: Icons.account_tree_outlined, label: 'Commit', disabled: _running, onTap: () => _run(RuntimeActionType.gitCommit)),
              _RuntimeActionButton(icon: Icons.publish_outlined, label: 'Publish', disabled: _running, onTap: () => _run(RuntimeActionType.publishPages)),
              _RuntimeActionButton(icon: Icons.history_outlined, label: 'Recover', disabled: _running, onTap: _inspectTask),
              _RuntimeActionButton(icon: Icons.manage_history_outlined, label: 'History', disabled: _running, onTap: _inspectHistory),
              _RuntimeActionButton(icon: Icons.subject_outlined, label: 'Task detail', disabled: _running, onTap: _openTaskDetails),
            ],
          ),
          const SizedBox(height: 12),
          if (_lastProjectProfile != null) ...[
            _RuntimeProjectProfilePanel(profile: _lastProjectProfile!),
            const SizedBox(height: 12),
          ],
          if (_lastTask != null) ...[
            _TaskSnapshotPanel(
              task: _lastTask,
              onStop: _lastTask!.canCancel ? () => _cancelTask(_lastTask!.taskId) : null,
              onOpenDetails: () => _showRuntimeTaskDetailsSheet(
                context: context,
                runtimeManager: widget.runtimeManager,
                task: _lastTask!,
                onLog: widget.onLog,
              ),
            ),
            const SizedBox(height: 12),
          ],
          _Panel(
            child: Text(
              _lines.take(8).join('\n\n'),
              style: const TextStyle(color: _muted, fontSize: 12, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _RuntimeProjectProfilePanel extends StatelessWidget {
  const _RuntimeProjectProfilePanel({required this.profile});

  final RuntimeProjectProfile profile;

  @override
  Widget build(BuildContext context) {
    final color = profile.recognized ? _mint : _amber;
    final markers = profile.detectedFiles.take(6).join(', ');
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(profile.recognized ? Icons.folder_open_outlined : Icons.folder_outlined, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  profile.packageManager ?? 'No project profile',
                  style: const TextStyle(color: _text, fontWeight: FontWeight.w900),
                ),
              ),
              Text(profile.kind.name, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 6),
          Text(profile.summary, style: const TextStyle(color: _muted, fontSize: 12, height: 1.35)),
          if (markers.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(markers, style: const TextStyle(color: _muted, fontSize: 11, height: 1.25)),
          ],
          if (profile.recoveryHint != null) ...[
            const SizedBox(height: 6),
            Text(profile.recoveryHint!, style: TextStyle(color: color, fontSize: 11, height: 1.25)),
          ],
        ],
      ),
    );
  }
}

class _RuntimeHealthTile extends StatelessWidget {
  const _RuntimeHealthTile({required this.health});

  final RuntimeHealth health;

  @override
  Widget build(BuildContext context) {
    final planned = health.type == RuntimeProviderType.embeddedLite ||
        health.status.toLowerCase().contains('planned');
    final configuredLater = health.type == RuntimeProviderType.cloud && !health.ready;
    final color = health.ready
        ? _mint
        : planned || configuredLater
            ? _faint
            : health.available
                ? _amber
                : _rose;
    final label = health.ready
        ? 'ready'
        : planned
            ? 'planned'
            : configuredLater
                ? 'setup'
                : health.available
                    ? 'available'
                    : 'offline';
    final icon = health.ready
        ? Icons.check_circle_outline
        : planned || configuredLater
            ? Icons.event_note_outlined
            : Icons.info_outline;
    return _Panel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(health.name, style: const TextStyle(color: _text, fontWeight: FontWeight.w900)),
              ),
              Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 6),
          Text(health.status, style: const TextStyle(color: _muted, fontSize: 12, height: 1.35)),
          const SizedBox(height: 6),
          Text(_runtimeCapabilitiesText(health.capabilities), style: const TextStyle(color: _faint, fontSize: 11, height: 1.3)),
          if (health.missingDependencies.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              planned ? 'Planned: ${health.missingDependencies.join(', ')}' : 'Missing: ${health.missingDependencies.join(', ')}',
              style: TextStyle(color: planned ? _faint : _amber, fontSize: 11, height: 1.3),
            ),
          ],
          if (health.recoveryActions.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Recover: ${health.recoveryActions.join(' / ')}', style: const TextStyle(color: _muted, fontSize: 11, height: 1.3)),
          ],
        ],
      ),
    );
  }
}

class _DiagnosticLine extends StatelessWidget {
  const _DiagnosticLine({
    required this.label,
    required this.value,
    required this.good,
  });

  final String label;
  final String value;
  final bool good;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(good ? Icons.check_circle_outline : Icons.radio_button_unchecked_outlined, size: 16, color: good ? _mint : _faint),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(color: _muted, fontSize: 12))),
          Text(value, style: TextStyle(color: good ? _mint : _faint, fontSize: 12, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _TaskSnapshotPanel extends StatelessWidget {
  const _TaskSnapshotPanel({required this.task, this.onStop, this.onOpenDetails});

  final RuntimeTaskSnapshot? task;
  final VoidCallback? onStop;
  final VoidCallback? onOpenDetails;

  @override
  Widget build(BuildContext context) {
    final snapshot = task;
    if (snapshot == null) {
      return const _Panel(
        padding: EdgeInsets.all(12),
        child: Text('No recoverable runtime task snapshot yet.', style: TextStyle(color: _muted, fontSize: 12, height: 1.35)),
      );
    }
    final color = snapshot.running
        ? _amber
        : snapshot.status == RuntimeTaskStatus.succeeded
            ? _mint
            : _rose;
    final details = [
      if (snapshot.startedAt != null) 'Started ${_timeLabel(snapshot.startedAt!)} ago',
      if (snapshot.duration != null) 'Duration ${_durationLabel(snapshot.duration!)}',
      if (snapshot.exitCode != null) 'Exit ${snapshot.exitCode}',
      if (snapshot.failureKind != RuntimeTaskFailureKind.none) 'Failure ${snapshot.failureKind.name}',
    ];
    return _Panel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history_outlined, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text('Task ${snapshot.taskId}', style: const TextStyle(color: _text, fontWeight: FontWeight.w900))),
              Text(snapshot.status.name, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800)),
              if (onOpenDetails != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Open task details',
                  visualDensity: VisualDensity.compact,
                  onPressed: onOpenDetails,
                  icon: const Icon(Icons.subject_outlined, size: 18),
                  color: _cyan,
                ),
              ],
              if (snapshot.canCancel && onStop != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Stop task',
                  visualDensity: VisualDensity.compact,
                  onPressed: onStop,
                  icon: const Icon(Icons.stop_circle_outlined, size: 18),
                  color: _amber,
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(snapshot.command.isEmpty ? 'No command recorded.' : snapshot.command, style: const TextStyle(color: _muted, fontSize: 12, height: 1.35)),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final detail in details) _TaskDetailChip(label: detail, color: color),
              ],
            ),
          ],
          if (snapshot.workingDir != null && snapshot.workingDir!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(snapshot.workingDir!, style: const TextStyle(color: _faint, fontSize: 11, height: 1.3)),
          ],
          if (snapshot.error != null && snapshot.error!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(snapshot.error!, style: const TextStyle(color: _rose, fontSize: 11, height: 1.3)),
          ],
          if (runtimeFailureKindHint(snapshot.failureKind) != null) ...[
            const SizedBox(height: 6),
            Text('Recovery: ${runtimeFailureKindHint(snapshot.failureKind)!}', style: const TextStyle(color: _amber, fontSize: 11, height: 1.3)),
          ],
          if (snapshot.logs.isNotEmpty) ...[
            const SizedBox(height: 8),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                initiallyExpanded: snapshot.running || snapshot.status != RuntimeTaskStatus.succeeded,
                title: const Text('Recent logs', style: TextStyle(color: _muted, fontSize: 12, fontWeight: FontWeight.w800)),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(_recentLogLines(snapshot.logs, limit: 8).join('\n'), style: const TextStyle(color: _faint, fontSize: 11, height: 1.3)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TaskDetailChip extends StatelessWidget {
  const _TaskDetailChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
    );
  }
}

void _showRuntimeTaskDetailsSheet({
  required BuildContext context,
  required RuntimeManager runtimeManager,
  required RuntimeTaskSnapshot task,
  required void Function(String title, String detail, IconData icon, Color color) onLog,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: _panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
    ),
    builder: (context) => _RuntimeTaskDetailSheet(
      runtimeManager: runtimeManager,
      initialTask: task,
      onLog: onLog,
    ),
  );
}

class _RuntimeTaskDetailSheet extends StatefulWidget {
  const _RuntimeTaskDetailSheet({
    required this.runtimeManager,
    required this.initialTask,
    required this.onLog,
  });

  final RuntimeManager runtimeManager;
  final RuntimeTaskSnapshot initialTask;
  final void Function(String title, String detail, IconData icon, Color color) onLog;

  @override
  State<_RuntimeTaskDetailSheet> createState() => _RuntimeTaskDetailSheetState();
}

class _RuntimeTaskDetailSheetState extends State<_RuntimeTaskDetailSheet> {
  late RuntimeTaskSnapshot _task;
  List<RuntimeTaskSnapshot> _tasks = const [];
  bool _loading = false;
  bool _retrying = false;
  bool _stopping = false;
  String _status = 'Task detail is ready.';
  DateTime? _lastRefresh;
  Timer? _poller;

  @override
  void initState() {
    super.initState();
    _task = widget.initialTask;
    _tasks = [_task];
    unawaited(_refresh());
    _poller = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      if (_task.running || _tasks.any((task) => task.running)) {
        unawaited(_refresh(silent: true));
      }
    });
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _status = 'Refreshing task ${_task.taskId}...';
      });
    }
    try {
      final tasks = await widget.runtimeManager.taskHistory(limit: 24);
      var selected = _task;
      for (final candidate in tasks) {
        if (candidate.taskId == _task.taskId) {
          selected = candidate;
          break;
        }
      }
      var logs = selected.logs;
      if (selected.taskId.trim().isNotEmpty) {
        final recoveredLogs = await widget.runtimeManager.taskLogs(selected.taskId, limit: 300);
        if (recoveredLogs.isNotEmpty) logs = recoveredLogs;
      }
      if (!mounted) return;
      setState(() {
        _tasks = tasks;
        _task = selected.copyWith(logs: logs);
        _lastRefresh = DateTime.now();
        _status = 'Task ${_task.taskId} is ${_task.status.name}.';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Task refresh failed: ${_compact(error.toString(), limit: 160)}');
    } finally {
      if (!silent && mounted) setState(() => _loading = false);
    }
  }

  Future<void> _stopTask() async {
    setState(() {
      _stopping = true;
      _status = 'Stopping task ${_task.taskId}...';
    });
    try {
      await widget.runtimeManager.stopTask(_task.taskId);
      await _refresh(silent: true);
      widget.onLog('Runtime task stop requested', 'Task ${_task.taskId}', Icons.stop_circle_outlined, _amber);
    } on Object catch (error) {
      if (!mounted) return;
      final message = _compact(error.toString(), limit: 160);
      setState(() => _status = 'Stop failed: $message');
      widget.onLog('Runtime task stop failed', message, Icons.error_outline, _rose);
    } finally {
      if (mounted) setState(() => _stopping = false);
    }
  }

  Future<void> _retryTask() async {
    final command = _task.command.trim();
    if (command.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Task has no command to retry.')));
      return;
    }
    setState(() {
      _retrying = true;
      _status = 'Retrying task ${_task.taskId}...';
    });
    try {
      final result = await widget.runtimeManager.execute(
        command,
        workingDir: _task.workingDir,
        timeout: const Duration(minutes: 10),
      );
      final tasks = await widget.runtimeManager.taskHistory(limit: 24);
      RuntimeTaskSnapshot? nextTask;
      final nextTaskId = result.taskId;
      if (nextTaskId != null && nextTaskId.isNotEmpty) {
        for (final candidate in tasks) {
          if (candidate.taskId == nextTaskId) {
            nextTask = candidate;
            break;
          }
        }
      }
      nextTask ??= tasks.isEmpty ? null : tasks.first;
      final fallbackLogs = [
        if (result.stdout.trim().isNotEmpty) ...result.stdout.trim().split('\n'),
        if (result.stderr.trim().isNotEmpty) ...result.stderr.trim().split('\n'),
      ];
      if (!mounted) return;
      setState(() {
        _tasks = tasks;
        _task = nextTask ??
            _task.copyWith(
              status: result.success ? RuntimeTaskStatus.succeeded : RuntimeTaskStatus.failed,
              exitCode: result.exitCode,
              duration: result.duration,
              logs: fallbackLogs,
              failureKind: result.failureKind,
            );
        _status = result.success ? 'Retry completed successfully.' : 'Retry failed with exit ${result.exitCode}.';
      });
      widget.onLog(
        result.success ? 'Runtime task retry completed' : 'Runtime task retry failed',
        'Original ${widget.initialTask.taskId} -> ${result.taskId ?? 'no task id'}',
        result.success ? Icons.replay_circle_filled_outlined : Icons.error_outline,
        result.success ? _mint : _rose,
      );
    } on Object catch (error) {
      if (!mounted) return;
      final message = _compact(error.toString(), limit: 160);
      setState(() => _status = 'Retry failed: $message');
      widget.onLog('Runtime task retry error', message, Icons.error_outline, _rose);
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  Future<void> _copyFailureSummary() async {
    await Clipboard.setData(ClipboardData(text: _failureSummary()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Task summary copied.')));
    widget.onLog('Runtime failure summary copied', 'Task ${_task.taskId}', Icons.copy_outlined, _cyan);
  }

  String _failureSummary() {
    final lines = <String>[
      'Task: ${_task.taskId}',
      'Status: ${_task.status.name}',
      'Command: ${_task.command.isEmpty ? '(empty)' : _task.command}',
      if (_task.workingDir != null && _task.workingDir!.isNotEmpty) 'cwd: ${_task.workingDir}',
      if (_task.startedAt != null) 'Started: ${_task.startedAt!.toIso8601String()}',
      if (_task.duration != null) 'Duration: ${_durationLabel(_task.duration!)}',
      if (_task.exitCode != null) 'Exit code: ${_task.exitCode}',
      if (_task.failureKind != RuntimeTaskFailureKind.none) 'Failure kind: ${_task.failureKind.name}',
      if (_task.error != null && _task.error!.isNotEmpty) 'Error: ${_task.error}',
      if (runtimeFailureKindHint(_task.failureKind) != null) 'Recovery: ${runtimeFailureKindHint(_task.failureKind)!}',
    ];
    final logs = _recentLogLines(_task.logs, limit: 24);
    if (logs.isNotEmpty) {
      lines
        ..add('Recent logs:')
        ..addAll(logs);
    }
    return lines.join('\n');
  }

  Color _statusColor(RuntimeTaskSnapshot task) {
    if (task.running) return _amber;
    return task.status == RuntimeTaskStatus.succeeded ? _mint : _rose;
  }

  void _selectTask(RuntimeTaskSnapshot task) {
    setState(() {
      _task = task;
      _status = 'Selected task ${task.taskId}.';
    });
    unawaited(_refresh(silent: true));
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(_task);
    final queuedTasks = _tasks.where((task) => task.status == RuntimeTaskStatus.queued).toList();
    final logs = _recentLogLines(_task.logs, limit: 120);
    final detailChips = [
      _task.status.name,
      if (_task.startedAt != null) 'started ${_timeLabel(_task.startedAt!)} ago',
      if (_task.duration != null) 'duration ${_durationLabel(_task.duration!)}',
      if (_task.exitCode != null) 'exit ${_task.exitCode}',
      if (_task.failureKind != RuntimeTaskFailureKind.none) _task.failureKind.name,
    ];
    return _SheetScaffold(
      icon: Icons.subject_outlined,
      title: 'Runtime Task Detail',
      subtitle: 'Live logs, task retry, failure summary, and queue visibility.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Panel(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.bolt_outlined, color: color, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Task ${_task.taskId}', style: const TextStyle(color: _text, fontWeight: FontWeight.w900))),
                    Text(_lastRefresh == null ? 'not synced' : 'synced ${_timeLabel(_lastRefresh!)} ago', style: const TextStyle(color: _faint, fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(_status, style: const TextStyle(color: _muted, fontSize: 12, height: 1.35)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final detail in detailChips) _TaskDetailChip(label: detail, color: color),
                  ],
                ),
                const SizedBox(height: 8),
                SelectableText(_task.command.isEmpty ? 'No command recorded.' : _task.command, style: const TextStyle(color: _muted, fontSize: 12, height: 1.35)),
                if (_task.workingDir != null && _task.workingDir!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  SelectableText(_task.workingDir!, style: const TextStyle(color: _faint, fontSize: 11, height: 1.3)),
                ],
                if (_task.error != null && _task.error!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(_task.error!, style: const TextStyle(color: _rose, fontSize: 11, height: 1.3)),
                ],
                if (runtimeFailureKindHint(_task.failureKind) != null) ...[
                  const SizedBox(height: 6),
                  Text('Recovery: ${runtimeFailureKindHint(_task.failureKind)!}', style: const TextStyle(color: _amber, fontSize: 11, height: 1.3)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _RuntimeActionButton(icon: Icons.refresh_outlined, label: _loading ? 'Refreshing' : 'Refresh', disabled: _loading, onTap: () => unawaited(_refresh())),
              _RuntimeActionButton(icon: Icons.stop_circle_outlined, label: _stopping ? 'Stopping' : 'Stop', disabled: _stopping || !_task.canCancel, onTap: () => unawaited(_stopTask())),
              _RuntimeActionButton(icon: Icons.replay_outlined, label: _retrying ? 'Retrying' : 'Retry taskId', disabled: _retrying || _task.command.trim().isEmpty, onTap: () => unawaited(_retryTask())),
              _RuntimeActionButton(icon: Icons.copy_outlined, label: 'Copy failure', disabled: false, onTap: () => unawaited(_copyFailureSummary())),
            ],
          ),
          const SizedBox(height: 12),
          _Panel(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Queue', style: TextStyle(color: _text, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                if (queuedTasks.isEmpty)
                  const Text('No queued runtime tasks.', style: TextStyle(color: _muted, fontSize: 12, height: 1.35))
                else
                  for (final task in queuedTasks) ...[
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.pending_actions_outlined, color: _amber),
                      title: Text('Task ${task.taskId}', style: const TextStyle(color: _text, fontWeight: FontWeight.w800)),
                      subtitle: Text(_compact(task.command, limit: 96), style: const TextStyle(color: _muted, fontSize: 12)),
                      trailing: IconButton(
                        tooltip: 'Inspect queued task',
                        onPressed: () => _selectTask(task),
                        icon: const Icon(Icons.open_in_new_outlined, size: 18),
                      ),
                    ),
                  ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Panel(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Live logs', style: TextStyle(color: _text, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      logs.isEmpty ? 'No logs recovered for this task yet.' : logs.join('\n'),
                      style: const TextStyle(color: _faint, fontSize: 11, height: 1.3),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectConsoleSheet extends StatefulWidget {
  const _ProjectConsoleSheet({
    required this.runtimeManager,
    required this.defaultProjectPath,
    required this.onLog,
  });

  final RuntimeManager runtimeManager;
  final String defaultProjectPath;
  final void Function(String title, String detail, IconData icon, Color color) onLog;

  @override
  State<_ProjectConsoleSheet> createState() => _ProjectConsoleSheetState();
}

class _ProjectConsoleSheetState extends State<_ProjectConsoleSheet> {
  final _projectName = TextEditingController();
  final _projectPath = TextEditingController();
  final _gitUrl = TextEditingController();
  final List<String> _lines = ['No project action has run yet.'];
  List<String> _recentProjectPaths = const [];
  bool _running = false;
  RuntimeProjectProfile? _profile;

  @override
  void initState() {
    super.initState();
    _projectPath.text = widget.defaultProjectPath;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadRecentProjects());
    });
  }

  @override
  void dispose() {
    _projectName.dispose();
    _projectPath.dispose();
    _gitUrl.dispose();
    super.dispose();
  }

  Future<void> _loadRecentProjects() async {
    setState(() {
      _running = true;
      _lines.insert(0, 'Loading recent runtime project paths...');
    });
    try {
      final tasks = await widget.runtimeManager.taskHistory(limit: 12);
      final paths = <String>{};
      for (final task in tasks) {
        final path = task.workingDir?.trim();
        if (path != null && path.isNotEmpty) paths.add(path);
      }
      if (_profile?.projectPath.trim().isNotEmpty == true) {
        paths.add(_profile!.projectPath.trim());
      }
      if (!mounted) return;
      setState(() {
        _recentProjectPaths = paths.take(6).toList();
        _lines.insert(0, paths.isEmpty ? 'No recent runtime project paths found.' : 'Loaded ${paths.length} recent project path(s).');
      });
    } on Object catch (error) {
      if (!mounted) return;
      final message = _compact(error.toString(), limit: 180);
      setState(() => _lines.insert(0, 'RECENT PROJECTS ERROR: $message'));
      widget.onLog('Recent project load failed', message, Icons.error_outline, _rose);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _cloneRepository() async {
    final url = _gitUrl.text.trim();
    final validationError = _gitUrlError(url);
    if (validationError != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(validationError)));
      return;
    }
    final targetName = _safeProjectDirectoryName(_projectName.text.trim().isEmpty ? _projectNameFromGitUrl(url) : _projectName.text.trim());
    final targetPath = '${widget.defaultProjectPath}/$targetName';
    setState(() {
      _running = true;
      _lines.insert(0, 'Cloning repository into $targetPath...');
    });
    try {
      final result = await widget.runtimeManager.execute(
        'git clone ${_quoteCommandArg(url)} ${_quoteCommandArg(targetName)}',
        workingDir: widget.defaultProjectPath,
        timeout: const Duration(minutes: 10),
      );
      if (!mounted) return;
      setState(() {
        _projectPath.text = targetPath;
        _recentProjectPaths = [targetPath, ..._recentProjectPaths.where((path) => path != targetPath)].take(6).toList();
        _lines.insert(
          0,
          [
            result.success ? 'CLONED: $targetPath' : 'CLONE FAILED: $targetPath',
            if (result.stdout.trim().isNotEmpty) _compact(result.stdout.trim(), limit: 220),
            if (result.stderr.trim().isNotEmpty) _compact(result.stderr.trim(), limit: 220),
          ].join('\n'),
        );
      });
      widget.onLog(
        result.success ? 'Git repository cloned' : 'Git clone failed',
        targetPath,
        result.success ? Icons.download_done_outlined : Icons.error_outline,
        result.success ? _mint : _rose,
      );
    } on Object catch (error) {
      if (!mounted) return;
      final message = _compact(error.toString(), limit: 180);
      setState(() => _lines.insert(0, 'CLONE ERROR: $message'));
      widget.onLog('Git clone error', message, Icons.error_outline, _rose);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _runPreflight() async {
    final path = _projectPath.text.trim();
    if (path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Project path is required')));
      return;
    }
    setState(() {
      _running = true;
      _lines.insert(0, 'Running project preflight...');
    });
    try {
      final profile = await widget.runtimeManager.preflightProject(path);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _lines.insert(
          0,
          [
            'PREFLIGHT: ${profile.summary}',
            if (profile.recoveryHint != null) 'Recovery: ${profile.recoveryHint!}',
          ].join('\n'),
        );
      });
      widget.onLog(
        profile.recognized ? 'Project detected' : 'Project needs setup',
        profile.summary,
        profile.recognized ? Icons.search_outlined : Icons.warning_amber_outlined,
        profile.recognized ? _mint : _amber,
      );
    } on Object catch (error) {
      if (!mounted) return;
      final message = _compact(error.toString(), limit: 180);
      setState(() => _lines.insert(0, 'PREFLIGHT ERROR: $message'));
      widget.onLog('Project preflight error', message, Icons.error_outline, _rose);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _runValidation() async {
    final path = _projectPath.text.trim();
    if (path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Project path is required')));
      return;
    }
    setState(() {
      _running = true;
      _lines.insert(0, 'Running project validation...');
    });
    try {
      final result = await widget.runtimeManager.validateProject(
        projectPath: path,
        message: _projectName.text.trim().isEmpty ? null : _projectName.text.trim(),
      );
      if (!mounted) return;
      final stepLines = result.steps.map((s) => '${s.success ? 'OK' : 'FAILED'} ${s.action.name}: ${s.summary}');
      setState(() {
        _profile = result.profile;
        _lines.insert(
          0,
          [
            result.success ? 'VALIDATED: ${result.summary}' : 'VALIDATION STOPPED: ${result.summary}',
            ...stepLines,
            if (result.recoveryHint != null) 'Recovery: ${result.recoveryHint!}',
          ].join('\n'),
        );
      });
      widget.onLog(
        result.success ? 'Project validated' : 'Project validation stopped',
        result.summary,
        result.success ? Icons.verified_outlined : Icons.error_outline,
        result.success ? _mint : _rose,
      );
    } on Object catch (error) {
      if (!mounted) return;
      final message = _compact(error.toString(), limit: 180);
      setState(() => _lines.insert(0, 'VALIDATION ERROR: $message'));
      widget.onLog('Project validation error', message, Icons.error_outline, _rose);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  void _fillDefaultPath() {
    setState(() {
      _projectPath.text = widget.defaultProjectPath;
      _lines.insert(0, 'Project path set to runtime workspace default.');
    });
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      icon: Icons.folder_open_outlined,
      title: 'Project Console',
      subtitle: 'Configure project name and path, then run preflight or validation through the active runtime.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _projectName,
            decoration: const InputDecoration(labelText: 'Project name (optional)', prefixIcon: Icon(Icons.badge_outlined)),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _projectPath,
            decoration: const InputDecoration(labelText: 'Project path / cwd', prefixIcon: Icon(Icons.folder_outlined)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _RuntimeActionButton(
                icon: Icons.home_work_outlined,
                label: 'Default cwd',
                disabled: _running,
                onTap: _fillDefaultPath,
              ),
              _RuntimeActionButton(
                icon: Icons.manage_history_outlined,
                label: 'Recent paths',
                disabled: _running,
                onTap: _loadRecentProjects,
              ),
              _RuntimeActionButton(
                icon: Icons.search_outlined,
                label: 'Preflight',
                disabled: _running,
                onTap: _runPreflight,
              ),
              _RuntimeActionButton(
                icon: Icons.verified_outlined,
                label: 'Validate',
                disabled: _running,
                onTap: _runValidation,
              ),
            ],
          ),
          if (_recentProjectPaths.isNotEmpty) ...[
            const SizedBox(height: 10),
            _Panel(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final path in _recentProjectPaths)
                    ActionChip(
                      avatar: const Icon(Icons.folder_open_outlined, size: 16),
                      label: Text(_compact(path, limit: 34)),
                      onPressed: _running ? null : () => setState(() => _projectPath.text = path),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _gitUrl,
            decoration: const InputDecoration(labelText: 'Git repository URL', prefixIcon: Icon(Icons.cloud_download_outlined)),
          ),
          const SizedBox(height: 8),
          _RuntimeActionButton(
            icon: Icons.download_outlined,
            label: 'Clone / import Git',
            disabled: _running,
            onTap: _cloneRepository,
          ),
          const SizedBox(height: 12),
          if (_profile != null) ...[
            _RuntimeProjectProfilePanel(profile: _profile!),
            const SizedBox(height: 12),
          ],
          _Panel(
            child: Text(
              _lines.take(8).join('\n\n'),
              style: const TextStyle(color: _muted, fontSize: 12, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _RuntimeActionButton extends StatelessWidget {
  const _RuntimeActionButton({
    required this.icon,
    required this.label,
    required this.disabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: disabled ? null : onTap,
      icon: Icon(icon, size: 17),
      label: Text(label),
    );
  }
}

String _runtimeCapabilitiesText(RuntimeCapabilities capabilities) {
  final labels = <String>[
    if (capabilities.shell) 'shell',
    if (capabilities.git) 'git',
    if (capabilities.node) 'node',
    if (capabilities.python) 'python',
    if (capabilities.flutter) 'flutter',
    if (capabilities.androidBuild) 'apk',
    if (capabilities.pty) 'pty',
    if (capabilities.backgroundService) 'background',
    if (capabilities.cloudBuild) 'cloud',
    if (capabilities.webViewPreview) 'webview',
  ];
  return labels.isEmpty ? 'webview-only' : labels.join(', ');
}

String _boolStatus(bool? value) {
  if (value == true) return 'yes';
  if (value == false) return 'no';
  return 'unknown';
}

class _ChatPanel extends StatefulWidget {
  const _ChatPanel({
    super.key,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.providerPreset,
    required this.managedProviderPresets,
    required this.relayUrl,
    required this.relayToken,
    required this.browserOpenMode,
    required this.onLog,
    required this.onAgentPrompt,
    required this.onProviderPresetSelected,
    this.onSessionsChanged,
    this.embedded = false,
  });

  final String baseUrl;
  final String apiKey;
  final String model;
  final _ProviderPreset providerPreset;
  final List<_ProviderPreset> managedProviderPresets;
  final String relayUrl;
  final String relayToken;
  final String browserOpenMode;
  final void Function(String title, String detail, IconData icon, Color color) onLog;
  final Future<void> Function(String prompt) onAgentPrompt;
  final ValueChanged<_ProviderPreset> onProviderPresetSelected;
  final void Function(List<_ChatSession> sessions, String? activeSessionId)? onSessionsChanged;
  final bool embedded;

  @override
  State<_ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<_ChatPanel> {
  static const _sessionsKey = 'mobilecode.chat.sessions.v1';
  static const _activeSessionKey = 'mobilecode.chat.activeSession.v1';

  final _promptController = TextEditingController();
  final _chatScrollController = ScrollController();
  final _voiceService = VoiceService();
  final List<_ChatSession> _sessions = [];
  Future<void>? _sessionLoadFuture;
  String? _activeSessionId;
  bool _loading = true;
  bool _sending = false;
  bool _agentRunning = false;
  bool _agentStopping = false;
  bool _agentCancelRequested = false;
  bool _agentModeEnabled = false;
  AgentExecutionMode _agentExecutionMode = AgentExecutionMode.singleShot;
  AgentPreset _agentPreset = AgentPreset.autoAgent;
  bool _followChatBottom = true;
  bool _showJumpToBottom = false;
  bool _autoScrollScheduled = false;
  HttpClient? _agentProviderClient;
  bool _voiceAvailable = false;
  VoiceState _voiceState = VoiceState.idle;
  StreamSubscription<String>? _voiceTranscriptSub;
  StreamSubscription<VoiceState>? _voiceStateSub;
  String? _error;
  GitHubRepoChatRequest? _repoBinding;
  List<MobileCodeRole> _roleRecruitRoles = RoleLibraryService.instance.recruitmentRoles;
  List<MobileCodeRole>? _activeRunRoles;
  RoleProposal? _activeRunProposal;
  final List<_AgentTraceStep> _agentTrace = [];
  final Set<String> _agentTraceEventKeys = {};
  final List<String> _agentProviderLiveProcess = [];
  final Map<String, int> _agentProviderLiveProcessKeys = {};
  final Map<String, int> _agentStreamTraceIndexes = {};
  final ActionEvidenceStore _agentEvidenceStore = ActionEvidenceStore.shared;
  final Map<String, GlobalKey> _turnKeys = {};
  Timer? _navPreviewTimer;
  _ChatNavPreview? _navPreview;
  int? _lastNavActiveIndex;

  _ChatSession? get _activeSession {
    if (_sessions.isEmpty) return null;
    final index = _sessions.indexWhere((session) => session.id == _activeSessionId);
    return index == -1 ? _sessions.first : _sessions[index];
  }

  List<MobileCodeRole> get _displayRecruitRoles => _activeRunRoles ?? _roleRecruitRoles;

  @override
  void initState() {
    super.initState();
    _chatScrollController.addListener(_handleChatScroll);
    RoleLibraryService.instance.addListener(_handleRoleLibraryChanged);
    unawaited(RoleLibraryService.instance.initialize().then((_) {
      if (!mounted) return;
      setState(() => _roleRecruitRoles = RoleLibraryService.instance.recruitmentRoles);
    }));
    unawaited(TokenUsageService.instance.initialize());
    _sessionLoadFuture = _loadSessions();
    _initVoiceInput();
  }

  @override
  void dispose() {
    _agentProviderClient?.close(force: true);
    RoleLibraryService.instance.removeListener(_handleRoleLibraryChanged);
    _voiceTranscriptSub?.cancel();
    _voiceStateSub?.cancel();
    _navPreviewTimer?.cancel();
    _voiceService.dispose();
    _chatScrollController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  void _handleRoleLibraryChanged() {
    if (!mounted) return;
    setState(() => _roleRecruitRoles = RoleLibraryService.instance.recruitmentRoles);
  }

  Future<void> _initVoiceInput() async {
    _voiceTranscriptSub = _voiceService.onTranscriptUpdate.listen((text) {
      if (!mounted || text.trim().isEmpty) return;
      _promptController.text = text;
      _promptController.selection = TextSelection.collapsed(offset: _promptController.text.length);
      setState(() {});
    });
    _voiceStateSub = _voiceService.onStateChange.listen((state) {
      if (!mounted) return;
      setState(() => _voiceState = state);
    });
    final available = await _voiceService.initialize();
    if (!mounted) return;
    setState(() {
      _voiceAvailable = available;
      _voiceState = _voiceService.currentState;
    });
  }

  Future<void> _ensureSessionsLoaded() async {
    final pendingLoad = _sessionLoadFuture;
    if (!_loading || pendingLoad == null) return;
    await pendingLoad;
  }

  Future<void> _loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionsKey);
    final savedActiveId = prefs.getString(_activeSessionKey);
    final loaded = <_ChatSession>[];

    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          loaded.addAll(
            decoded
                .whereType<Map>()
                .map((item) => _ChatSession.fromJson(Map<String, dynamic>.from(item)))
                .where((session) {
                  if (session.turns.isNotEmpty) return true;
                  if (session.id == savedActiveId) return true;
                  return session.title.trim().isNotEmpty && session.title.trim() != 'New chat';
                }),
          );
        }
      } catch (_) {
        // Corrupt chat storage should not block the chat surface.
      }
    }

    if (loaded.isEmpty) loaded.add(_newSessionObject());
    loaded.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    if (!mounted) return;
    setState(() {
      _sessions
        ..clear()
        ..addAll(loaded.take(20));
      _activeSessionId = savedActiveId;
      if (_sessions.every((session) => session.id != _activeSessionId)) {
        _activeSessionId = _sessions.first.id;
      }
      _loading = false;
    });
    _notifySessionsChanged();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final activeId = _activeSessionId;
    final persistedSessions = _sessions.where((session) {
      if (session.turns.isNotEmpty) return true;
      if (session.id == activeId) return true;
      return session.title.trim().isNotEmpty && session.title.trim() != 'New chat';
    }).take(20).toList();
    await prefs.setString(_sessionsKey, jsonEncode(persistedSessions.map((session) => session.toJson()).toList()));
    if (activeId != null) {
      await prefs.setString(_activeSessionKey, activeId);
    }
    _notifySessionsChanged();
  }

  void _notifySessionsChanged() {
    widget.onSessionsChanged?.call(List<_ChatSession>.unmodifiable(_sessions), _activeSessionId);
  }

  Future<void> createSessionFromShell() => _createSession();

  Future<void> selectSessionFromShell(String id) => _selectSession(id);

  Future<void> bindRepoFromShell(GitHubRepoChatRequest request) async {
    await _ensureSessionsLoaded();
    if (!mounted) return;
    setState(() => _repoBinding = request);
    _scrollConversationToEnd(force: true);
  }

  Future<void> setPromptFromShell(String prompt, {bool runAgent = false}) async {
    await _ensureSessionsLoaded();
    if (!mounted) return;
    _promptController.text = prompt;
    _promptController.selection = TextSelection.collapsed(offset: prompt.length);
    setState(() {});
    if (runAgent) {
      unawaited(_runAgentWithTrace());
    }
  }

  _ChatSession _newSessionObject() {
    final now = DateTime.now();
    return _ChatSession(
      id: now.microsecondsSinceEpoch.toString(),
      title: 'New chat',
      createdAt: now,
      updatedAt: now,
      turns: const [],
    );
  }

  void _storeSession(_ChatSession session) {
    final index = _sessions.indexWhere((item) => item.id == session.id);
    if (index == -1) {
      _sessions.insert(0, session);
    } else {
      _sessions[index] = session;
      _sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }
  }

  Future<void> _createSession() async {
    await _ensureSessionsLoaded();
    if (!mounted) return;
    final active = _activeSession;
    if (active != null && active.turns.isEmpty && active.title == 'New chat') {
      setState(() {
        _activeSessionId = active.id;
        _error = null;
        _repoBinding = null;
        _promptController.clear();
      });
      _notifySessionsChanged();
      await _persist();
      return;
    }
    final session = _newSessionObject();
    setState(() {
      _sessions.insert(0, session);
      _activeSessionId = session.id;
      _error = null;
      _repoBinding = null;
      _promptController.clear();
    });
    _notifySessionsChanged();
    await _persist();
  }

  Future<void> _selectSession(String id) async {
    await _ensureSessionsLoaded();
    if (!mounted) return;
    setState(() {
      _activeSessionId = id;
      _error = null;
      _repoBinding = null;
    });
    _notifySessionsChanged();
    await _persist();
  }

  Future<void> _deleteActiveSession() async {
    final active = _activeSession;
    if (active == null) return;
    setState(() {
      _sessions.removeWhere((session) => session.id == active.id);
      if (_sessions.isEmpty) {
        final replacement = _newSessionObject();
        _sessions.add(replacement);
        _activeSessionId = replacement.id;
      } else {
        _activeSessionId = _sessions.first.id;
      }
      _error = null;
    });
    await _persist();
  }

  Future<void> _send() async {
    await _ensureSessionsLoaded();
    if (!mounted) return;
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      _showMessage('Enter a prompt first');
      return;
    }
    final active = _activeSession;
    if (active == null) {
      _showMessage('Chat is still loading');
      return;
    }

    final now = DateTime.now();
    final userTurn = _ChatTurn(role: 'user', content: prompt, time: now);
    final history = [...active.turns, userTurn];
    final pending = active.copyWith(
      title: active.title == 'New chat' ? _chatTitle(prompt) : active.title,
      updatedAt: now,
      turns: history,
    );

    setState(() {
      _sending = true;
      _error = null;
      _promptController.clear();
      _storeSession(pending);
    });
    _scrollConversationToEnd(force: true);
    await _persist();

    final flavor = _detectApiFlavor(widget.baseUrl, widget.model);
    final repoContext = _repoBindingContext();
    final systemPrompt = [
      'You are MobileCode, a mobile AI development assistant. Use the saved multi-turn chat context, answer concisely, and prefer executable mobile development steps.',
      if (repoContext.isNotEmpty) ...[
        '',
        repoContext,
      ],
    ].join('\n');
    final runId = 'chat_${DateTime.now().microsecondsSinceEpoch}';
    final usageAccumulator = TokenUsageAccumulator(providerKind: _usageProviderKind(flavor));
    final usageStarted = DateTime.now();
    final answerBuffer = StringBuffer();
    try {
      final assistantStarted = DateTime.now();
      var lastPaintAt = DateTime.fromMillisecondsSinceEpoch(0);
      var lastPaintLength = 0;
      await for (final chunk in _streamProvider(
        history,
        systemPrompt: systemPrompt,
        responseTimeout: const Duration(minutes: 2),
        onUsageChunk: usageAccumulator.addChunk,
      )) {
        answerBuffer.write(chunk);
        final answer = answerBuffer.toString();
        final now = DateTime.now();
        if (now.difference(lastPaintAt).inMilliseconds <= 220 &&
            answer.length - lastPaintLength < 120) {
          continue;
        }
        lastPaintAt = now;
        lastPaintLength = answer.length;
        _replaceAssistantTurn(
          sessionId: pending.id,
          assistantIndex: history.length,
          content: answer,
          time: assistantStarted,
        );
      }

      final answer = answerBuffer.toString().trim();
      if (answer.isEmpty) {
        throw Exception('Provider stream completed without text.');
      }
      _replaceAssistantTurn(
        sessionId: pending.id,
        assistantIndex: history.length,
        content: answer,
        time: assistantStarted,
      );
      if (!mounted) return;
      _scrollConversationToEnd();
      await _persist();
      await TokenUsageService.instance.recordCompleted(
        provider: _flavorLabel(flavor),
        model: widget.model,
        endpoint: 'chat',
        durationMs: DateTime.now().difference(usageStarted).inMilliseconds,
        success: true,
        sessionId: pending.id,
        runId: runId,
        usage: usageAccumulator.snapshot(
          inputChars: _tokenInputChars(history, systemPrompt),
          outputChars: answer.length,
        ),
      );
      widget.onLog('AI response streamed', '${_flavorLabel(flavor)} - ${widget.model} - ${answer.length} chars', Icons.forum_outlined, _mint);
    } on Object catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst('Exception: ', '');
      setState(() => _error = message);
      await TokenUsageService.instance.recordCompleted(
        provider: _flavorLabel(flavor),
        model: widget.model,
        endpoint: 'chat',
        durationMs: DateTime.now().difference(usageStarted).inMilliseconds,
        success: false,
        sessionId: pending.id,
        runId: runId,
        usage: usageAccumulator.snapshot(
          inputChars: _tokenInputChars(history, systemPrompt),
          outputChars: answerBuffer.length,
        ),
      );
      widget.onLog('AI request error', _compact(message, limit: 140), Icons.error_outline, _rose);
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  void _replaceAssistantTurn({
    required String sessionId,
    required int assistantIndex,
    required String content,
    required DateTime time,
  }) {
    if (!mounted) return;
    final sessionIndex = _sessions.indexWhere((item) => item.id == sessionId);
    if (sessionIndex == -1) return;
    final session = _sessions[sessionIndex];
    final turns = [...session.turns];
    final replacement = _ChatTurn(role: 'assistant', content: content, time: time);
    if (assistantIndex >= 0 &&
        assistantIndex < turns.length &&
        turns[assistantIndex].role == 'assistant') {
      turns[assistantIndex] = replacement;
    } else {
      turns.add(replacement);
    }
    setState(() {
      _storeSession(session.copyWith(updatedAt: DateTime.now(), turns: turns));
    });
    _scrollConversationToEnd();
  }

  Future<void> _toggleVoiceInput() async {
    if (!_voiceAvailable) {
      final available = await _voiceService.initialize();
      if (!mounted) return;
      setState(() => _voiceAvailable = available);
      if (!available) {
        _showMessage(_voiceService.lastError.isEmpty ? 'Voice input is not available' : _voiceService.lastError);
        return;
      }
    }

    final voiceActive = _voiceService.isListening || _voiceState == VoiceState.listening;
    if (voiceActive) {
      setState(() => _voiceState = VoiceState.processing);
      String transcript;
      try {
        transcript = await _voiceService.stopListening().timeout(const Duration(seconds: 2));
      } on TimeoutException {
        await _voiceService.cancel();
        transcript = _promptController.text;
      }
      if (!mounted) return;
      if (transcript.trim().isNotEmpty) {
        _promptController.text = transcript.trim();
        _promptController.selection = TextSelection.collapsed(offset: _promptController.text.length);
      }
      setState(() => _voiceState = _voiceService.currentState);
      return;
    }

    try {
      await _voiceService.startListening();
      if (mounted) setState(() => _voiceState = VoiceState.listening);
    } on Object catch (error) {
      if (!mounted) return;
      _showMessage(_compact(error.toString(), limit: 120));
      setState(() => _voiceState = VoiceState.error);
    }
  }

  String _usageProviderKind(_ApiFlavor flavor) {
    return flavor == _ApiFlavor.anthropic ? 'anthropic' : 'openai';
  }

  int _tokenInputChars(List<_ChatTurn> turns, String systemPrompt) {
    return systemPrompt.length + turns.fold<int>(0, (total, turn) => total + turn.content.length + turn.role.length + 8);
  }

  bool get _usesManagedRelay => widget.relayUrl.trim().isNotEmpty && widget.providerPreset != _ProviderPreset.custom;

  Uri _managedRelayUri() {
    final normalized = _normalizedBaseUrl(widget.relayUrl.trim());
    if (normalized.endsWith('/v1/provider')) return Uri.parse(normalized);
    return Uri.parse('$normalized/v1/provider');
  }

  Uri _managedRelayToolUri(String toolName) {
    var normalized = _normalizedBaseUrl(widget.relayUrl.trim());
    if (normalized.endsWith('/v1/provider')) {
      normalized = normalized.substring(0, normalized.length - '/v1/provider'.length);
    }
    return Uri.parse('$normalized/v1/tools/$toolName');
  }

  Map<String, dynamic> _relayEnvelope(_ApiFlavor flavor, Map<String, dynamic> body) {
    return {
      'provider': widget.providerPreset.name,
      'flavor': _usageProviderKind(flavor),
      'body': body,
    };
  }

  Future<Map<String, dynamic>> _callManagedRelayWebTool(
    String toolName,
    Map<String, dynamic> payload,
  ) async {
    if (!_usesManagedRelay) {
      throw Exception('Relay web tool `$toolName` requires managed relay mode.');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client.postUrl(_managedRelayToolUri(toolName)).timeout(const Duration(seconds: 12));
      request.headers.contentType = ContentType.json;
      if (widget.relayToken.trim().isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${widget.relayToken.trim()}');
      }
      request.headers.set('x-mobilecode-provider', widget.providerPreset.name);
      request.write(jsonEncode({
        'provider': widget.providerPreset.name,
        'input': payload,
      }));
      final response = await request.close().timeout(const Duration(seconds: 45));
      final rawBody = await utf8.decodeStream(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Relay tool HTTP ${response.statusCode}: ${_compact(rawBody, limit: 240)}');
      }
      final decoded = jsonDecode(rawBody);
      if (decoded is Map<String, dynamic>) return decoded;
      throw Exception('Relay tool `$toolName` returned a non-object response.');
    } on SocketException catch (error) {
      throw Exception('Relay tool network error: ${_friendlySocketError(error)}');
    } on TimeoutException {
      throw Exception('Relay tool `$toolName` timed out.');
    } finally {
      client.close(force: true);
    }
  }

  void _configureProviderRequestHeaders(HttpClientRequest request, _ApiFlavor flavor) {
    request.headers.contentType = ContentType.json;
    if (_usesManagedRelay) {
      if (widget.relayToken.trim().isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${widget.relayToken.trim()}');
      }
      request.headers.set('x-mobilecode-provider', widget.providerPreset.name);
      return;
    }
    if (flavor == _ApiFlavor.anthropic) {
      request.headers.set('anthropic-version', '2023-06-01');
      request.headers.set('x-api-key', widget.apiKey);
    }
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${widget.apiKey}');
  }

  Future<String> _callProvider(
    List<_ChatTurn> history, {
    required String systemPrompt,
    int maxTokens = 1024,
    Duration responseTimeout = const Duration(seconds: 120),
    bool trackAgentRequest = false,
    bool Function()? isCancelled,
  }) async {
    if (widget.baseUrl.trim().isEmpty) {
      throw Exception('Provider is not configured: Base URL is empty.');
    }
    if (!_usesManagedRelay && widget.apiKey.trim().isEmpty) {
      throw Exception('Provider is not configured: API key is empty.');
    }
    if (isCancelled?.call() == true) {
      throw Exception('Agent run stopped by user.');
    }

    final flavor = _detectApiFlavor(widget.baseUrl, widget.model);
    final requestBody = _requestBody(
      flavor,
      history,
      systemPrompt: systemPrompt,
      maxTokens: maxTokens,
      stream: false,
    );
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    if (trackAgentRequest) {
      _agentProviderClient = client;
    }
    try {
      final request = await client.postUrl(
        _usesManagedRelay
            ? _managedRelayUri()
            : flavor == _ApiFlavor.anthropic
                ? _anthropicMessagesUri(widget.baseUrl)
                : _openAiChatUri(widget.baseUrl),
      ).timeout(const Duration(seconds: 12));
      if (isCancelled?.call() == true) {
        throw Exception('Agent run stopped by user.');
      }
      _configureProviderRequestHeaders(request, flavor);
      request.write(jsonEncode(_usesManagedRelay ? _relayEnvelope(flavor, requestBody) : requestBody));

      final response = await request.close().timeout(responseTimeout);
      if (isCancelled?.call() == true) {
        throw Exception('Agent run stopped by user.');
      }
      final rawBody = await utf8.decodeStream(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Provider HTTP ${response.statusCode}: ${_compact(rawBody)}');
      }
      final answer = _extractAssistantText(rawBody);
      if (answer.trim().isEmpty) {
        throw Exception('Provider returned an empty response.');
      }
      return answer;
    } on SocketException catch (error) {
      if (isCancelled?.call() == true) {
        throw Exception('Agent run stopped by user.');
      }
      throw Exception('Provider network error: ${_friendlySocketError(error)}');
    } on HttpException catch (error) {
      if (isCancelled?.call() == true) {
        throw Exception('Agent run stopped by user.');
      }
      throw Exception('Provider HTTP error: ${error.message}');
    } on TimeoutException {
      throw Exception('Provider timed out after ${responseTimeout.inSeconds}s while waiting for a model response. Try a shorter prompt/model output or stop and retry.');
    } finally {
      if (identical(_agentProviderClient, client)) {
        _agentProviderClient = null;
      }
      client.close(force: true);
    }
  }

  Stream<String> _streamProvider(
    List<_ChatTurn> history, {
    required String systemPrompt,
    int maxTokens = 1024,
    Duration responseTimeout = const Duration(seconds: 180),
    bool trackAgentRequest = false,
    bool Function()? isCancelled,
    void Function(Map<String, dynamic> chunk)? onUsageChunk,
  }) async* {
    if (widget.baseUrl.trim().isEmpty) {
      throw Exception('Provider is not configured: Base URL is empty.');
    }
    if (!_usesManagedRelay && widget.apiKey.trim().isEmpty) {
      throw Exception('Provider is not configured: API key is empty.');
    }
    if (isCancelled?.call() == true) {
      throw Exception('Agent run stopped by user.');
    }

    final flavor = _detectApiFlavor(widget.baseUrl, widget.model);
    final requestBody = _requestBody(
      flavor,
      history,
      systemPrompt: systemPrompt,
      maxTokens: maxTokens,
      stream: true,
    );
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    if (trackAgentRequest) {
      _agentProviderClient = client;
    }

    try {
      final request = await client.postUrl(
        _usesManagedRelay
            ? _managedRelayUri()
            : flavor == _ApiFlavor.anthropic
                ? _anthropicMessagesUri(widget.baseUrl)
                : _openAiChatUri(widget.baseUrl),
      ).timeout(const Duration(seconds: 12));
      if (isCancelled?.call() == true) {
        throw Exception('Agent run stopped by user.');
      }

      _configureProviderRequestHeaders(request, flavor);
      request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      request.write(jsonEncode(_usesManagedRelay ? _relayEnvelope(flavor, requestBody) : requestBody));

      final response = await request.close().timeout(responseTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = await utf8.decodeStream(response);
        throw Exception('Provider HTTP ${response.statusCode}: ${_compact(body)}');
      }

        await for (final line in response
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .timeout(responseTimeout)) {
          if (isCancelled?.call() == true) {
            throw Exception('Agent run stopped by user.');
          }
          final event = parseOpenAiStreamEvent(line);
          if (event.isIgnore) continue;
          if (event.isDone) break;
          final payload = event.payload;

        try {
          final decoded = jsonDecode(payload);
          if (decoded is Map<String, dynamic>) {
            onUsageChunk?.call(decoded);
            if (decoded['type'] == 'message_stop') break;
            final delta = _extractStreamDelta(decoded, flavor);
            if (delta != null && delta.isNotEmpty) {
              yield delta;
            }
            continue;
          }
        } catch (_) {
          if (payload.startsWith('{')) {
            final fallback = _extractAssistantText(payload);
            if (fallback.trim().isNotEmpty) yield fallback.trim();
            break;
          }
        }
      }
    } on SocketException catch (error) {
      if (isCancelled?.call() == true) {
        throw Exception('Agent run stopped by user.');
      }
      throw Exception('Provider network error: ${_friendlySocketError(error)}');
    } on HttpException catch (error) {
      if (isCancelled?.call() == true) {
        throw Exception('Agent run stopped by user.');
      }
      throw Exception('Provider HTTP error: ${error.message}');
    } on TimeoutException {
      throw Exception('Provider stream timed out after ${responseTimeout.inSeconds}s. Use Pause to stop long runs or reduce requested output.');
    } finally {
      if (identical(_agentProviderClient, client)) {
        _agentProviderClient = null;
      }
      client.close(force: true);
    }
  }

  OpenAiCompatibleToolCallAdapter? _providerNativeToolCallAdapter() {
    final profile = ToolCallProviderProfile.detect(widget.baseUrl, widget.model);
    if (!profile.supportsNativeToolCalls || !profile.isOpenAiCompatible) {
      return null;
    }
    return OpenAiCompatibleToolCallAdapter(profile: profile);
  }

  Future<ProviderToolCallResponse> _streamOpenAiCompatibleToolCallRequest(
    OpenAiCompatibleToolCallAdapter adapter,
    Map<String, dynamic> body, {
    required Duration responseTimeout,
    bool Function()? isCancelled,
    void Function(Map<String, dynamic> chunk)? onUsageChunk,
    void Function(String detail)? onToolDelta,
  }) async {
    if (widget.baseUrl.trim().isEmpty) {
      throw Exception('Provider is not configured: Base URL is empty.');
    }
    if (!_usesManagedRelay && widget.apiKey.trim().isEmpty) {
      throw Exception('Provider is not configured: API key is empty.');
    }
    if (isCancelled?.call() == true) {
      throw Exception('Agent run stopped by user.');
    }

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    _agentProviderClient = client;
    final toolAssembler = OpenAiToolCallStreamAssembler();
    final announcedTools = <String>{};
    final announcedArgumentBuckets = <String, int>{};
    String? finishReason;

    try {
      final request = await client.postUrl(_usesManagedRelay ? _managedRelayUri() : _openAiChatUri(widget.baseUrl)).timeout(const Duration(seconds: 12));
      if (isCancelled?.call() == true) {
        throw Exception('Agent run stopped by user.');
      }
      _configureProviderRequestHeaders(request, _ApiFlavor.openAi);
      request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      request.write(jsonEncode(_usesManagedRelay ? _relayEnvelope(_ApiFlavor.openAi, body) : body));

      final response = await request.close().timeout(responseTimeout);
      if (isCancelled?.call() == true) {
        throw Exception('Agent run stopped by user.');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final rawBody = await utf8.decodeStream(response);
        throw Exception('Provider HTTP ${response.statusCode}: ${_compact(rawBody)}');
      }

      await for (final line in response
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(responseTimeout)) {
        if (isCancelled?.call() == true) {
          throw Exception('Agent run stopped by user.');
        }
        final event = parseOpenAiStreamEvent(line);
        if (event.isIgnore) continue;
        if (event.isDone) break;
        final payload = event.payload;

        try {
          final decoded = jsonDecode(payload);
          if (decoded is! Map<String, dynamic>) continue;
          onUsageChunk?.call(decoded);

          final nonStreamingFallback = _maybeParseNonStreamingToolCall(adapter, decoded);
          if (nonStreamingFallback != null) return nonStreamingFallback;

          toolAssembler.addChunk(decoded);
          finishReason ??= _extractOpenAiFinishReason(decoded);

          for (final toolName in _extractOpenAiStreamingToolNames(decoded)) {
            if (announcedTools.add(toolName)) {
              onToolDelta?.call('model is selecting provider-native tool `$toolName`.');
            }
          }
          for (final progress in toolAssembler.progress) {
            final toolName = progress.name;
            if (toolName == null || toolName.trim().isEmpty || progress.argumentChars < 800) {
              continue;
            }
            final bucket = progress.argumentChars ~/ 1600;
            final key = progress.key;
            if (announcedArgumentBuckets[key] != bucket) {
              announcedArgumentBuckets[key] = bucket;
              final pathLabel = progress.targetPath == null ? '' : ', target `${progress.targetPath}`';
              onToolDelta?.call('receiving `$toolName` arguments (${progress.argumentChars} chars streamed, ${progress.argumentLines} lines$pathLabel).');
            }
          }
        } catch (_) {
          if (payload.startsWith('{')) {
            final fallback = _extractAssistantText(payload);
            if (fallback.trim().isNotEmpty) {
              return ProviderToolCallResponse(content: fallback.trim(), toolCalls: const []);
            }
          }
        }
      }
    } on SocketException catch (error) {
      if (isCancelled?.call() == true) {
        throw Exception('Agent run stopped by user.');
      }
      throw Exception('Provider network error: ${_friendlySocketError(error)}');
    } on HttpException catch (error) {
      if (isCancelled?.call() == true) {
        throw Exception('Agent run stopped by user.');
      }
      throw Exception('Provider HTTP error: ${error.message}');
    } on TimeoutException {
      throw Exception('Provider stream timed out after ${responseTimeout.inSeconds}s while waiting for tool-call deltas.');
    } finally {
      if (identical(_agentProviderClient, client)) {
        _agentProviderClient = null;
      }
      client.close(force: true);
    }

    final reasoning = toolAssembler.reasoningContent.trim();
    return ProviderToolCallResponse(
      content: toolAssembler.content.trim(),
      toolCalls: toolAssembler.finish(),
      finishReason: finishReason,
      reasoningContent: reasoning.isEmpty ? null : reasoning,
    );
  }

  ProviderToolCallResponse? _maybeParseNonStreamingToolCall(
    OpenAiCompatibleToolCallAdapter adapter,
    Map<String, dynamic> decoded,
  ) {
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final first = choices.first;
    if (first is! Map<String, dynamic>) return null;
    if (first['message'] is Map<String, dynamic>) {
      return adapter.parseChatCompletion(decoded);
    }
    return null;
  }

  List<String> _extractOpenAiStreamingToolNames(Map<String, dynamic> decoded) {
    final names = <String>[];
    final choices = decoded['choices'];
    if (choices is! List) return names;
    for (final choice in choices) {
      if (choice is! Map<String, dynamic>) continue;
      final delta = choice['delta'];
      if (delta is! Map<String, dynamic>) continue;
      final toolCalls = delta['tool_calls'];
      if (toolCalls is! List) continue;
      for (final raw in toolCalls) {
        if (raw is! Map<String, dynamic>) continue;
        final function = raw['function'];
        if (function is! Map<String, dynamic>) continue;
        final name = function['name'];
        if (name is String && name.trim().isNotEmpty) names.add(name.trim());
      }
    }
    return names;
  }

  String? _extractOpenAiFinishReason(Map<String, dynamic> decoded) {
    final choices = decoded['choices'];
    if (choices is! List) return null;
    for (final choice in choices) {
      if (choice is! Map<String, dynamic>) continue;
      final reason = choice['finish_reason'];
      if (reason is String && reason.isNotEmpty) return reason;
    }
    return null;
  }

  Future<AgentLoopResult?> _runProviderNativeToolLoop(
    List<_ChatTurn> history, {
    required String systemPrompt,
    required TokenUsageAccumulator usageAccumulator,
    required AgentPreset preset,
    required void Function(String detail) onStatus,
    void Function(AgentLoopEvent event)? onLoopEvent,
    void Function(int round, String detail)? onStreamStatus,
    bool Function()? isCancelled,
  }) async {
    final adapter = _providerNativeToolCallAdapter();
    if (adapter == null) return null;

    final rootDirectory = await _mobileCodeProjectsRootDirectory();
    final actionRunner = ActionRunner(
      workspaceRootPath: rootDirectory.path,
      evidenceStore: _agentEvidenceStore,
      webToolInvoker: _usesManagedRelay ? _callManagedRelayWebTool : null,
    );
    final messages = _providerMessages(history).map((message) => Map<String, dynamic>.from(message)).toList();
    final model = widget.model.trim().isEmpty ? 'deepseek-v4-flash' : widget.model.trim();
    final controller = AgentLoopController(
      adapter: adapter,
      actionRunner: actionRunner,
      preset: preset,
      maxRounds: 6,
    );

    return controller.run(
      initialMessages: messages,
      isCancelled: isCancelled,
      onEvent: (event) {
        final round = event.round == null ? '' : ' round ${event.round}';
        final tool = event.toolName == null ? '' : ' · ${event.toolName}';
        onStatus('${adapter.profile.label} ${preset.label}$round$tool: ${event.message}');
        onLoopEvent?.call(event);
      },
      requestModel: (loopMessages, {required round}) async {
        return _streamOpenAiCompatibleToolCallRequest(
          adapter,
          adapter.buildChatCompletionRequest(
            model: model,
            systemPrompt: systemPrompt,
            messages: loopMessages,
            maxTokens: 4096,
            stream: true,
            toolChoice: ToolChoiceMode.auto,
            allowedToolNames: controller.allowedToolNames,
          ),
          responseTimeout: const Duration(minutes: 3),
          isCancelled: isCancelled,
          onUsageChunk: usageAccumulator.addChunk,
          onToolDelta: (detail) {
            onStatus('${adapter.profile.label} ${preset.label} round $round: $detail');
            onStreamStatus?.call(round, detail);
          },
        );
      },
    );
  }

  Future<void> _runAgentWithTrace() async {
    await _ensureSessionsLoaded();
    if (!mounted) return;
    if (_agentRunning) {
      _showMessage('Agent is still running');
      return;
    }
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      _showMessage('Describe what the agent should build or test');
      return;
    }
    final active = _activeSession;
    if (active == null) {
      _showMessage('Chat is still loading');
      return;
    }

    final toolName = _agentToolNameForPrompt(prompt);
    if (_agentExecutionMode == AgentExecutionMode.agentLoop && _providerNativeToolCallAdapter() == null) {
      _showMessage('当前模型不支持 Agent Loop：请切换 DeepSeek/OpenAI-compatible，或改用 Single-shot。');
      return;
    }
    final runId = 'agent_${DateTime.now().microsecondsSinceEpoch}';
    RoleProposal? proposedRole;
    List<MobileCodeRole>? activeRoles;
    if (_agentModeEnabled) {
      await RoleLibraryService.instance.initialize();
      final enabledRoles = RoleLibraryService.instance.recruitmentRoles;
      proposedRole = await RoleLibraryService.instance.createProposalFromPrompt(prompt, runId, enabledRoles);
      if (proposedRole != null) {
        final sourceRoleId = proposedRole.sourceRoleId;
        activeRoles = [
          proposedRole.role,
          ...enabledRoles.where((role) => role.id != sourceRoleId).take(4),
        ];
      } else {
        activeRoles = enabledRoles;
      }
    }
    final now = DateTime.now();
    final pending = active.copyWith(
      title: active.title == 'New chat' ? _chatTitle(prompt) : active.title,
      updatedAt: now,
      turns: [
        ...active.turns,
        _ChatTurn(role: 'user', content: prompt, time: now),
      ],
    );

    setState(() {
      _agentRunning = true;
      _agentStopping = false;
      _agentCancelRequested = false;
      _error = null;
      _promptController.clear();
      _agentTrace
        ..clear()
        ..addAll(_agentRunTraceTemplate(prompt));
      _agentTraceEventKeys.clear();
      _agentProviderLiveProcess.clear();
      _agentProviderLiveProcessKeys.clear();
      _agentStreamTraceIndexes.clear();
      _activeRunRoles = activeRoles;
      _activeRunProposal = proposedRole;
      _storeSession(pending);
    });
    _scrollConversationToEnd(force: true);
    await _persist();

    String? failure;
    String? modelAnswer;
    String? generatedPath;
    var providerNativeHandledArtifacts = false;
    final flavor = _detectApiFlavor(widget.baseUrl, widget.model);
    final usageAccumulator = TokenUsageAccumulator(providerKind: _usageProviderKind(flavor));
    final agentStarted = DateTime.now();
    DateTime? providerStartedAt;
    try {
      await _completeAgentRunStep(0);
      if (_agentCancelRequested) throw Exception('Agent run stopped by user.');
      await _completeAgentRunStep(1);
      if (_agentCancelRequested) throw Exception('Agent run stopped by user.');
      final skillContext = toolName.startsWith('mobile_coding.generate_')
          ? await SkillManagerService.instance.buildHtmlGenerationSkillContext()
          : '';
      if (skillContext.isNotEmpty) {
        _setAgentRunStep(
          1,
          _AgentStepState.done,
          detail: 'Selected $toolName and injected enabled HTML/UI skills into the provider prompt.',
        );
      }
      final providerStarted = DateTime.now();
      providerStartedAt = providerStarted;
      _setAgentRunStep(
        2,
        _AgentStepState.running,
        detail: _agentExecutionMode == AgentExecutionMode.agentLoop
            ? 'Calling ${_flavorLabel(flavor)} provider in Agent Loop mode as ${_agentPreset.label}.'
            : 'Calling ${_flavorLabel(flavor)} provider in Single-shot mode. Native tool calls are skipped for stable fallback.',
      );

      final agentSystemPrompt = _agentSystemPrompt(
        toolName,
        skillContext: skillContext,
        roleContext: _agentModeEnabled ? _roleRecruitmentContext() : '',
      );
      final nativeLoop = _agentExecutionMode == AgentExecutionMode.agentLoop
          ? await _runProviderNativeToolLoop(
              pending.turns,
              systemPrompt: agentSystemPrompt,
              usageAccumulator: usageAccumulator,
              preset: _agentPreset,
              isCancelled: () => _agentCancelRequested,
              onStatus: (detail) => _setAgentRunStep(2, _AgentStepState.running, detail: detail),
              onLoopEvent: _appendAgentLoopTraceEvent,
              onStreamStatus: _appendAgentLoopStreamTraceEvent,
            )
          : null;

      if (nativeLoop != null) {
        if (nativeLoop.answer.trim().isEmpty) {
          throw Exception('Provider native tool-call request completed without text or tool observations.');
        }
        if (_agentExecutionMode == AgentExecutionMode.agentLoop && !nativeLoop.usedNativeToolCalls) {
          throw Exception('Agent Loop requires provider-native tool_calls, but the provider returned only text. Switch to Single-shot for text-only generation.');
        }
        modelAnswer = nativeLoop.answer;
        generatedPath = nativeLoop.generatedPath;
        providerNativeHandledArtifacts = nativeLoop.usedNativeToolCalls;
        final elapsed = DateTime.now().difference(providerStarted).inSeconds;
        _setAgentRunStep(
          2,
          _AgentStepState.done,
          detail: nativeLoop.usedNativeToolCalls
              ? 'Ran ${nativeLoop.toolCallCount} provider-native tool call(s) across ${nativeLoop.rounds} round(s) in ${elapsed}s.'
              : 'Provider returned no native tool calls; using generated-only fallback response in ${elapsed}s.',
        );
      } else {
        final streamBuffer = StringBuffer();
        var lastPreviewAt = DateTime.fromMillisecondsSinceEpoch(0);
        var lastPreviewLength = 0;
        await for (final chunk in _streamProvider(
          pending.turns,
          systemPrompt: agentSystemPrompt,
          maxTokens: 4096,
          responseTimeout: const Duration(minutes: 3),
          trackAgentRequest: true,
          isCancelled: () => _agentCancelRequested,
          onUsageChunk: usageAccumulator.addChunk,
        )) {
          if (_agentCancelRequested) throw Exception('Agent run stopped by user.');
          streamBuffer.write(chunk);
          final currentText = streamBuffer.toString();
          final now = DateTime.now();
          if (now.difference(lastPreviewAt).inMilliseconds > 350 ||
              currentText.length - lastPreviewLength >= 240) {
            lastPreviewAt = now;
            lastPreviewLength = currentText.length;
            final elapsed = now.difference(providerStarted).inSeconds;
            _setAgentRunStep(
              2,
              _AgentStepState.running,
              detail:
                  'Streaming provider output: ${currentText.length} chars in ${elapsed}s. Buffering content for validation instead of showing raw code in chat.',
            );
          }
        }
        final streamedAnswer = streamBuffer.toString();
        if (streamedAnswer.trim().isEmpty) {
          throw Exception('Provider stream completed without text.');
        }
        modelAnswer = streamedAnswer;
        final elapsed = DateTime.now().difference(providerStarted).inSeconds;
        _setAgentRunStep(2, _AgentStepState.done, detail: 'Streamed ${streamedAnswer.length} chars from ${_flavorLabel(flavor)} in ${elapsed}s.');
      }

      if (_agentCancelRequested) throw Exception('Agent run stopped by user.');
      if (!providerNativeHandledArtifacts &&
          _toolRequiresHtmlArtifact(toolName) &&
          _extractHtmlDocument(modelAnswer ?? '') == null) {
        _setAgentRunStep(
          2,
          _AgentStepState.running,
          detail: 'Provider response missed the required HTML artifact; asking once for a strict repair response.',
        );
        modelAnswer = await _repairMissingHtmlArtifactResponse(
          toolName: toolName,
          originalTurns: pending.turns,
          systemPrompt: agentSystemPrompt,
          originalAnswer: modelAnswer ?? '',
          isCancelled: () => _agentCancelRequested,
        );
        _setAgentRunStep(
          2,
          _AgentStepState.done,
          detail: 'Recovered a complete HTML artifact after one repair retry.',
        );
      }
      if (!providerNativeHandledArtifacts) {
        generatedPath = await _persistAgentGeneratedArtifact(toolName, modelAnswer);
      }
      if (_agentCancelRequested) throw Exception('Agent run stopped by user.');
      await _completeAgentRunStep(
        3,
        detail: generatedPath == null
            ? 'No file artifact required for this tool.'
            : providerNativeHandledArtifacts
                ? 'Provider-native tool call produced artifact at $generatedPath'
                : 'Saved generated artifact to $generatedPath',
      );
      if (_agentCancelRequested) throw Exception('Agent run stopped by user.');
      await _completeAgentRunStep(4);
    } on Object catch (error) {
      failure = error.toString();
      _failAgentRunStep(_compact(failure, limit: 140));
    }

    if (!mounted) return;
    final current = _sessions.firstWhere((session) => session.id == pending.id, orElse: () => pending);
    final stopped = failure != null && failure!.toLowerCase().contains('stopped by user');
    final executionSummary = _agentTraceSummaryText();
    final assistantText = failure == null
        ? _agentProviderCompletionMessage(
            toolName,
            modelAnswer ?? '',
            generatedPath,
            executionSummary: executionSummary,
          )
        : stopped
            ? 'Agent run stopped before writing more output for `$toolName`.$executionSummary'
            : 'Agent run failed while using `$toolName`.\n\n${_compact(failure!, limit: 300)}$executionSummary';
    final next = current.copyWith(
      updatedAt: DateTime.now(),
      turns: [
        ...current.turns,
        _ChatTurn(role: 'assistant', content: assistantText, time: DateTime.now()),
      ],
    );

    setState(() {
      _agentRunning = false;
      _agentStopping = false;
      _agentCancelRequested = false;
      _storeSession(next);
      if (failure != null && !stopped) _error = failure;
    });
    final roleId = _displayRecruitRoles.isEmpty ? null : _displayRecruitRoles.first.id;
    final durationBase = providerStartedAt ?? agentStarted;
    if (stopped) {
      await TokenUsageService.instance.recordCancelled(
        provider: _flavorLabel(flavor),
        model: widget.model,
        endpoint: toolName,
        durationMs: DateTime.now().difference(durationBase).inMilliseconds,
        sessionId: pending.id,
        runId: runId,
        roleId: roleId,
        inputChars: _tokenInputChars(pending.turns, _agentSystemPrompt(toolName, roleContext: _agentModeEnabled ? _roleRecruitmentContext() : '')),
        outputChars: modelAnswer?.length ?? 0,
      );
    } else {
      await TokenUsageService.instance.recordCompleted(
        provider: _flavorLabel(flavor),
        model: widget.model,
        endpoint: toolName,
        durationMs: DateTime.now().difference(durationBase).inMilliseconds,
        success: failure == null,
        sessionId: pending.id,
        runId: runId,
        roleId: roleId,
        usage: usageAccumulator.snapshot(
          inputChars: _tokenInputChars(pending.turns, _agentSystemPrompt(toolName, roleContext: _agentModeEnabled ? _roleRecruitmentContext() : '')),
          outputChars: modelAnswer?.length ?? 0,
        ),
      );
    }
    _scrollConversationToEnd();
    await _persist();

    if (failure == null) {
      widget.onLog('Agent run completed', toolName, Icons.psychology_alt_outlined, _violet);
      await widget.onAgentPrompt(prompt);
    } else if (stopped) {
      widget.onLog('Agent run stopped', toolName, Icons.pause_circle_outline, _amber);
    } else {
      widget.onLog('Agent run failed', _compact(failure, limit: 140), Icons.error_outline, _rose);
    }
  }

  void _cancelAgentRun() {
    if (!_agentRunning || _agentStopping) return;
    setState(() {
      _agentCancelRequested = true;
      _agentStopping = true;
    });
    _agentProviderClient?.close(force: true);
    _failAgentRunStep('Stopped by user.');
    widget.onLog('Agent pause requested', 'Current provider request will be closed and no more files will be written.', Icons.pause_circle_outline, _amber);
  }

  void _setAgentRunStep(int index, _AgentStepState state, {String? detail}) {
    if (!mounted || index < 0 || index >= _agentTrace.length) return;
    setState(() {
      final step = _agentTrace[index];
      final next = step.copyWith(
        state: state,
        detail: detail ?? step.detail,
        startedAt: state == _AgentStepState.running && step.evidence == null ? DateTime.now() : step.startedAt,
        finishedAt: state == _AgentStepState.done || state == _AgentStepState.failed ? DateTime.now() : null,
      );
      _agentTrace[index] = _withStepEvidence(next, state);
    });
    _scrollConversationToEnd();
  }

  void _syncProviderLiveProcessDetail() {
    final providerIndex = _agentTrace.indexWhere((step) => step.traceAction == MobileCodeAction.traceCallProvider);
    if (providerIndex == -1 || _agentProviderLiveProcess.isEmpty) return;
    final providerStep = _agentTrace[providerIndex];
    final details = Map<String, String>.from(providerStep.details);
    details['Live process'] = _agentProviderLiveProcess.join('\n');
    _agentTrace[providerIndex] = providerStep.copyWith(details: details);
  }

  void _appendProviderLiveProcessLine(String line, {String? collapseKey}) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;
    final stamped = '${_clockLabel(DateTime.now())} · $trimmed';
    final existingIndex = collapseKey == null ? null : _agentProviderLiveProcessKeys[collapseKey];
    if (existingIndex != null && existingIndex >= 0 && existingIndex < _agentProviderLiveProcess.length) {
      _agentProviderLiveProcess[existingIndex] = stamped;
    } else if (_agentProviderLiveProcess.isNotEmpty && _agentProviderLiveProcess.last.endsWith(trimmed)) {
      _agentProviderLiveProcess[_agentProviderLiveProcess.length - 1] = stamped;
    } else {
      _agentProviderLiveProcess.add(stamped);
      if (collapseKey != null) {
        _agentProviderLiveProcessKeys[collapseKey] = _agentProviderLiveProcess.length - 1;
      }
    }
    if (_agentProviderLiveProcess.length > 18) {
      final removeCount = _agentProviderLiveProcess.length - 18;
      _agentProviderLiveProcess.removeRange(0, removeCount);
      _agentProviderLiveProcessKeys.removeWhere((_, index) => index < removeCount);
      for (final entry in _agentProviderLiveProcessKeys.entries.toList()) {
        _agentProviderLiveProcessKeys[entry.key] = entry.value - removeCount;
      }
    }
    _syncProviderLiveProcessDetail();
  }

  String _agentLoopEventLiveLine(AgentLoopEvent event) {
    final round = event.round == null ? '' : 'Round ${event.round}: ';
    final tool = event.toolName == null ? '' : ' `${event.toolName}`';
    final role = event.roleName == null ? '' : '${event.roleName}: ';
    return switch (event.type) {
      AgentLoopEventType.started => '${role}Agent Loop started.',
      AgentLoopEventType.modelRequest => '$round${role}asking model for the next tool call.',
      AgentLoopEventType.toolCall => '$round${role}selected tool$tool.',
      AgentLoopEventType.observation => '$round${role}received observation from$tool: ${event.success == false ? 'failed' : 'ok'}.',
      AgentLoopEventType.blocked => '$round${role}blocked tool$tool.',
      AgentLoopEventType.completed => '$round${role}completed: ${_compact(event.message, limit: 120)}',
      AgentLoopEventType.failed => '$round${role}failed in$tool: ${_compact(event.message, limit: 120)}',
    };
  }

  void _appendAgentLoopTraceEvent(AgentLoopEvent event) {
    if (!mounted) return;
    final key = [
      event.type.name,
      event.round ?? '',
      event.toolName ?? '',
      event.roleName ?? '',
      event.evidenceId ?? '',
      event.message,
    ].join('|');
    if (!_agentTraceEventKeys.add(key)) return;
    final state = event.type == AgentLoopEventType.failed ? _AgentStepState.failed : _AgentStepState.done;
    final rolePrefix = event.roleName == null ? '' : '${event.roleName} · ';
    final title = switch (event.type) {
      AgentLoopEventType.started => '${rolePrefix}Agent loop started',
      AgentLoopEventType.modelRequest => '${rolePrefix}Ask model for next action',
      AgentLoopEventType.toolCall => '${rolePrefix}Tool call: ${event.toolName ?? 'unknown'}',
      AgentLoopEventType.observation => '${rolePrefix}Observation: ${event.toolName ?? 'tool'}',
      AgentLoopEventType.blocked => '${rolePrefix}Blocked: ${event.toolName ?? 'tool'}',
      AgentLoopEventType.completed => '${rolePrefix}Agent loop summary',
      AgentLoopEventType.failed => '${rolePrefix}Failed: ${event.toolName ?? 'tool'}',
    };
    final action = switch (event.type) {
      AgentLoopEventType.toolCall => MobileCodeAction.traceSelectTool,
      AgentLoopEventType.observation => MobileCodeAction.traceReportChat,
      AgentLoopEventType.completed => MobileCodeAction.traceReportChat,
      AgentLoopEventType.failed => MobileCodeAction.traceReportChat,
      _ => MobileCodeAction.traceCallProvider,
    };
    final icon = switch (event.type) {
      AgentLoopEventType.started => Icons.play_circle_outline,
      AgentLoopEventType.modelRequest => Icons.psychology_alt_outlined,
      AgentLoopEventType.toolCall => Icons.account_tree_outlined,
      AgentLoopEventType.observation => Icons.fact_check_outlined,
      AgentLoopEventType.blocked => Icons.block_outlined,
      AgentLoopEventType.completed => Icons.summarize_outlined,
      AgentLoopEventType.failed => Icons.error_outline,
    };
    final round = event.round == null ? '' : 'Round ${event.round}: ';
    final step = _AgentTraceStep(
      title: title,
      detail: '$round${event.message}',
      icon: icon,
      toolName: event.toolName,
      details: {
        if (event.roleName != null) 'Role': event.roleName!,
        if (event.evidenceId != null) 'Evidence ID': event.evidenceId!,
      },
      traceAction: action,
      state: state,
      startedAt: event.createdAt,
      finishedAt: DateTime.now(),
    );
    setState(() {
      _appendProviderLiveProcessLine(_agentLoopEventLiveLine(event));
      _agentTrace.add(_withStepEvidence(step, state));
    });
    _scrollConversationToEnd();
  }

  void _appendAgentLoopStreamTraceEvent(int round, String detail) {
    if (!mounted) return;
    final toolMatch = RegExp(r'`([^`]+)`').firstMatch(detail);
    final toolName = toolMatch?.group(1) ?? 'tool';
    final charsMatch = RegExp(r'\((\d+) chars streamed').firstMatch(detail);
    final linesMatch = RegExp(r',\s*(\d+) lines').firstMatch(detail);
    final pathMatch = RegExp(r'target `([^`]+)`').firstMatch(detail);
    final currentChars = charsMatch == null ? null : int.tryParse(charsMatch.group(1)!);
    final currentLines = linesMatch == null ? null : int.tryParse(linesMatch.group(1)!);
    final targetPath = pathMatch?.group(1);
    final streamKey = 'stream|$round|$toolName';
    final existingIndex = _agentStreamTraceIndexes[streamKey] ?? -1;
    final previousChars = existingIndex == -1 ? null : int.tryParse(_agentTrace[existingIndex].details['Streamed chars'] ?? '');
    final deltaChars = currentChars == null || previousChars == null ? currentChars : currentChars - previousChars;
    final deltaLabel = deltaChars == null || deltaChars <= 0 ? '' : ' (+$deltaChars)';
    final mergedDetail = currentChars == null
        ? 'Round $round: model selected `$toolName`; waiting for structured arguments.'
        : 'Round $round: receiving `$toolName` arguments: $currentChars chars$deltaLabel${currentLines == null ? '' : ', $currentLines lines'}${targetPath == null ? '' : ', target $targetPath'}.';
    final details = {
      'Tool': toolName,
      'Stage': currentChars == null ? 'Tool selected' : 'Receiving tool arguments',
      if (currentChars != null) 'Streamed chars': '$currentChars',
      if (currentLines != null) 'Draft lines': '$currentLines',
      if (targetPath != null) 'Target path': targetPath,
      if (deltaChars != null && deltaChars > 0) 'Delta chars': '+$deltaChars',
      'Draft status': currentChars == null ? 'Tool selected' : 'Receiving; not executable yet',
      'Execution boundary': 'MobileCode buffers streamed arguments first; ActionRunner writes only after the complete tool call is received, parsed, validated, and allowed.',
    };
    final step = _AgentTraceStep(
      title: 'Streaming tool call: $toolName',
      detail: mergedDetail,
      icon: Icons.more_horiz_outlined,
      toolName: toolName,
      details: details,
      traceAction: MobileCodeAction.traceCallProvider,
      state: _AgentStepState.done,
      startedAt: DateTime.now(),
      finishedAt: DateTime.now(),
    );
    setState(() {
      _appendProviderLiveProcessLine(mergedDetail, collapseKey: streamKey);
      if (existingIndex == -1) {
        _agentTrace.add(_withStepEvidence(step, _AgentStepState.done));
        _agentStreamTraceIndexes[streamKey] = _agentTrace.length - 1;
      } else {
        final existing = _agentTrace[existingIndex];
        _agentTrace[existingIndex] = existing.copyWith(
          title: step.title,
          detail: step.detail,
          details: details,
          toolName: toolName,
          finishedAt: DateTime.now(),
        );
      }
    });
    _scrollConversationToEnd();
  }

  _AgentTraceStep _withStepEvidence(_AgentTraceStep step, _AgentStepState state) {
    switch (state) {
      case _AgentStepState.running:
        step.evidence = ActionEvidence(
          evidenceId: step.evidenceId,
          actionName: step.traceAction,
          paramsSummary: step.detail,
          startedAt: step.startedAt,
          endedAt: DateTime.now(),
          success: false,
          logs: [step.detail],
        );
        break;
      case _AgentStepState.done:
        step.evidence = ActionEvidence(
          evidenceId: step.evidenceId,
          actionName: step.traceAction,
          paramsSummary: step.detail,
          startedAt: step.startedAt,
          endedAt: DateTime.now(),
          success: true,
          artifactPaths: _traceArtifactPaths(step),
          logs: [step.detail],
        );
        break;
      case _AgentStepState.failed:
        step.evidence = ActionEvidence(
          evidenceId: step.evidenceId,
          actionName: step.traceAction,
          paramsSummary: step.detail,
          startedAt: step.startedAt,
          endedAt: DateTime.now(),
          success: false,
          failureKind: _traceFailureKind(step.detail),
          recoveryActions: _traceRecoveryActions(step),
          logs: [step.detail],
        );
        break;
      case _AgentStepState.queued:
        break;
    }
    final evidence = step.evidence;
    if (evidence != null) {
      _agentEvidenceStore.add(evidence);
    }
    return step;
  }

  List<String> _traceArtifactPaths(_AgentTraceStep step) {
    if (step.traceAction != MobileCodeAction.traceWriteArtifact) {
      return const [];
    }
    const marker = 'Saved generated artifact to ';
    final detail = step.detail.trim();
    if (!detail.startsWith(marker)) return const [];
    final path = detail.substring(marker.length).trim();
    return path.isEmpty ? const [] : [path];
  }

  String _traceFailureKind(String detail) {
    final lower = detail.toLowerCase();
    if (lower.contains('stopped') || lower.contains('cancel')) {
      return ActionFailureKind.cancelled;
    }
    if (lower.contains('timeout') || lower.contains('timed out')) {
      return ActionFailureKind.timeout;
    }
    if (lower.contains('api key') || lower.contains('token') || lower.contains('401') || lower.contains('403')) {
      return ActionFailureKind.authFailed;
    }
    if (lower.contains('provider') || lower.contains('http') || lower.contains('network')) {
      return ActionFailureKind.runtimeLost;
    }
    return ActionFailureKind.unknown;
  }

  List<String> _traceRecoveryActions(_AgentTraceStep step) {
    final failureKind = _traceFailureKind(step.detail);
    if (failureKind == ActionFailureKind.cancelled) {
      return const ['Run the agent again when ready.'];
    }
    if (failureKind == ActionFailureKind.timeout) {
      return const [
        'Retry with a smaller request or shorter output.',
        'Check provider latency before rerunning.',
      ];
    }
    if (failureKind == ActionFailureKind.authFailed) {
      return const ['Open Models & Settings and verify the provider token/base URL.'];
    }
    if (failureKind == ActionFailureKind.runtimeLost) {
      return const ['Refresh provider/runtime health, then retry the step.'];
    }
    return const ['Open step details and inspect the captured log before retrying.'];
  }

  Future<void> _completeAgentRunStep(int index, {String? detail}) async {
    if (!mounted || index < 0 || index >= _agentTrace.length) return;
    if (_agentCancelRequested) return;
    _setAgentRunStep(index, _AgentStepState.running);
    await Future<void>.delayed(const Duration(milliseconds: 240));
    if (!mounted || index < 0 || index >= _agentTrace.length) return;
    if (_agentCancelRequested) return;
    _setAgentRunStep(index, _AgentStepState.done, detail: detail);
  }

  void _failAgentRunStep(String detail) {
    if (!mounted || _agentTrace.isEmpty) return;
    final runningIndex = _agentTrace.indexWhere((step) => step.state == _AgentStepState.running);
    final index = runningIndex == -1 ? _agentTrace.indexWhere((step) => step.state == _AgentStepState.queued) : runningIndex;
    if (index == -1) return;
    setState(() {
      final failed = _agentTrace[index].copyWith(
        detail: detail,
        state: _AgentStepState.failed,
        finishedAt: DateTime.now(),
      );
      _agentTrace[index] = _withStepEvidence(failed, _AgentStepState.failed);
    });
    _scrollConversationToEnd();
  }

  void _openAgentRoleView(MobileCodeRole role, int index) {
    final step = index >= 0 && index < _agentTrace.length ? _agentTrace[index] : null;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _panel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(10))),
      builder: (context) => _AgentRoleViewSheet(
        role: role,
        index: index,
        step: step,
      ),
    );
  }

  Future<void> _acceptRoleProposal(RoleProposal proposal, {MobileCodeRole? editedRole}) async {
    await RoleLibraryService.instance.acceptProposal(proposal.proposalId, editedRole: editedRole);
    if (!mounted) return;
    setState(() {
      _activeRunProposal = null;
      _roleRecruitRoles = RoleLibraryService.instance.recruitmentRoles;
    });
    _showMessage('Role saved to local library');
  }

  Future<void> _dismissRoleProposal(RoleProposal proposal) async {
    await RoleLibraryService.instance.dismissProposal(proposal.proposalId);
    if (!mounted) return;
    setState(() => _activeRunProposal = null);
    _showMessage('Role proposal dismissed');
  }

  Future<void> _editRoleProposal(RoleProposal proposal) async {
    final edited = await showModalBottomSheet<MobileCodeRole>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _panel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(10))),
      builder: (context) => _RoleProposalEditSheet(role: proposal.role),
    );
    if (edited == null) return;
    await _acceptRoleProposal(proposal, editedRole: edited);
  }

  String _roleRecruitmentContext() {
    final roles = _displayRecruitRoles;
    if (roles.isEmpty) return '';
    final lines = <String>[
      'RR mode is enabled. Use these role cards as sequential role personalities inside one execution lane. Do not claim parallel execution.',
    ];
    for (var index = 0; index < roles.length; index++) {
      final role = roles[index];
      lines.add([
        '${index + 1}. ${role.name}',
        'Mission: ${role.mission}',
        if (role.personality.trim().isNotEmpty) 'Personality: ${role.personality}',
        if (role.responsibilities.isNotEmpty) 'Responsibilities: ${role.responsibilities.take(4).join('; ')}',
        if (role.guardrails.isNotEmpty) 'Guardrails: ${role.guardrails.take(3).join('; ')}',
        if (role.successCriteria.isNotEmpty) 'Success: ${role.successCriteria.take(3).join('; ')}',
        if (role.promptTemplate.trim().isNotEmpty) 'Prompt: ${role.promptTemplate}',
      ].join('\n'));
    }
    return lines.join('\n\n');
  }

  String _repoBindingContext() {
    final binding = _repoBinding;
    if (binding == null) return '';
    return [
      'Active GitHub repository binding:',
      '- Repository: ${binding.repoFullName}',
      '- Repository URL: ${binding.repoUrl}',
      if (binding.pagesUrl != null) '- GitHub Pages URL: ${binding.pagesUrl}',
      if (binding.actionsUrl != null) '- GitHub Actions URL: ${binding.actionsUrl}',
      '- Workspace mode: ${binding.workspaceMode}',
      if (binding.workspacePath != null) '- Phone workspace path: ${binding.workspacePath}',
      '- Remote-linked means GitHub API workspace, not a git clone. Use git commands only when workspace mode is Git clone.',
    ].join('\n');
  }

  String _agentSystemPrompt(String toolName, {String skillContext = '', String roleContext = ''}) {
    final repoContext = _repoBindingContext();
    return [
      'You are MobileCode Android tool-aware coding assistant.',
      'You are running inside a mobile app, so be honest about what has actually happened.',
      'The selected tool is `$toolName`.',
      'Execution mode: ${_agentExecutionMode.label}.',
      if (_agentExecutionMode == AgentExecutionMode.agentLoop) ...[
        'Agent preset: ${_agentPreset.label}.',
        _agentPreset.systemInstruction,
        'Allowed provider-native tools for this preset: ${_agentPreset.allowedToolNames.join(', ')}.',
        'Role flow is Planner -> Builder -> Reviewer -> Repair inside one mobile execution lane; it is not parallel sub-agent execution.',
        'Use provider-native tool calls for actions; do not claim files, previews, searches, or snapshots happened until MobileCode returns tool observations.',
      ] else ...[
        'Single-shot mode: answer once. MobileCode may save and preview generated artifacts after your response, but you must not claim provider-native tool execution happened.',
      ],
      if (repoContext.isNotEmpty) ...[
        '',
        repoContext,
      ],
      'You must generate original code from the user request. Do not use or mention a built-in demo fallback.',
      'Do not claim a file was written, previewed, pushed, or executed unless the app reports that after your response.',
      if (roleContext.isNotEmpty) ...[
        '',
        'Role Recruit / RR mode context:',
        roleContext,
      ],
      if (skillContext.isNotEmpty) ...[
        '',
        'Enabled HTML/UI skill context:',
        skillContext,
      ],
      if (toolName.startsWith('mobile_coding.generate_') && _agentExecutionMode == AgentExecutionMode.agentLoop)
        'For web/html Agent Loop requests, use list_files/find_files/grep_files if you need workspace context, write_file or apply_patch for a complete self-contained HTML document, then read_file/grep_files or preview_html, then report_result. Use move_file for safe rename/move requests instead of shell mv. After a successful mutation observation, inspect before mutating again. The HTML must be mobile-first, touch-friendly, accessible, visually intentional, GitHub Pages deployable, and not depend on network assets.',
      if (toolName.startsWith('mobile_coding.generate_') && _agentExecutionMode != AgentExecutionMode.agentLoop)
        'For web/html requests, return one complete self-contained HTML document inside a single ```html fenced block. It must be mobile-first, touch-friendly, accessible, visually intentional, GitHub Pages deployable, and not depend on network assets. Use relative links only; never reference app-private local paths inside the HTML.',
      if (toolName == 'mobile_coding.research_web_preview')
        'For the researched WebView demo, choose the smallest safe provider-native tool calls yourself from the allowed list. You may list workspace files, search public references, fetch public HTTPS pages, write/read/move a self-contained HTML artifact, preview it, capture preview evidence, or report the result depending on observations. Do not depend on network assets. Include useful refIds and evidence IDs in the final report.',
      if (toolName == 'mobile_coding.build_diary_demo')
        'For the diary app request, return the minimal implementable UI/data model plan and code snippets needed for a local APK diary experience.',
      if (toolName == 'mobile_tools.termux_probe')
        'For Termux/root requests, explain the Android permission/runtime boundary and list concrete checks without pretending shell execution happened.',
      if (toolName == 'github.connectivity_test')
        'For GitHub requests, describe the exact token/repo API checks and failure modes without inventing successful connectivity.',
      'Keep the answer concise but include enough code for the next local tool step.',
    ].join('\n');
  }

  String _agentProviderCompletionMessage(
    String toolName,
    String modelAnswer,
    String? generatedPath, {
    String executionSummary = '',
  }) {
    final isWebArtifact = generatedPath != null && _isWebArtifactPath(generatedPath);
    final answer = modelAnswer.trim();
    final loopStoppedAtSafetyLimit =
        answer.startsWith('Agent loop stopped after') || answer.startsWith('Agent loop reached the');
    final summary = loopStoppedAtSafetyLimit && generatedPath != null
        ? 'Agent Loop reached the safety limit after saving an artifact. MobileCode preserved the generated file and preview actions; repeated tool calls were stopped for safety.'
        : _assistantNonCodeSummary(answer);
    final shouldHideRawPayload = isWebArtifact || _looksLikeGeneratedArtifactPayload(answer);
    final lines = [
      'Agent run completed via provider: `$toolName`',
      if (generatedPath != null) ...[
        'Saved generated artifact: `$generatedPath`',
        'Phone file path: `$generatedPath`',
        'Code file: `$generatedPath`',
        if (isWebArtifact) 'Web preview: tap “网页预览” for in-app WebView or “浏览器打开” for the external browser.',
      ],
    ];
    if (summary.isNotEmpty) {
      lines
        ..add('')
        ..add(summary);
    }
    if (shouldHideRawPayload) {
      lines
        ..add('')
        ..add('生成代码已保存到上方文件，不再内联到聊天区；请点“代码文件”或“网页预览”查看。');
    } else if (answer.isNotEmpty && summary.isEmpty) {
      lines
        ..add('')
        ..add(answer);
    }
    if (executionSummary.trim().isNotEmpty) {
      lines
        ..add('')
        ..add(executionSummary.trim());
    }
    return lines.join('\n');
  }

  String _agentTraceSummaryText() {
    final visible = _agentTrace.where((step) => step.state != _AgentStepState.queued).toList();
    if (visible.isEmpty) return '';
    final capped = visible.length > 14 ? visible.sublist(visible.length - 14) : visible;
    final lines = <String>[
      '本轮执行总结',
      for (final step in capped)
        '- ${_agentStepLabel(step.state)} · ${step.title}: ${_compact(step.detail, limit: 140)}',
    ];
    if (visible.length > capped.length) {
      lines.insert(1, '- 已省略前 ${visible.length - capped.length} 条早期事件，可在上方过程面板查看。');
    }
    return '\n\n${lines.join('\n')}';
  }

  bool _toolRequiresHtmlArtifact(String toolName) {
    return toolName == 'mobile_coding.generate_snake_preview' ||
        toolName == 'mobile_coding.generate_2048_preview' ||
        toolName == 'mobile_coding.generate_web_preview' ||
        toolName == 'mobile_coding.research_web_preview';
  }

  Future<String> _repairMissingHtmlArtifactResponse({
    required String toolName,
    required List<_ChatTurn> originalTurns,
    required String systemPrompt,
    required String originalAnswer,
    bool Function()? isCancelled,
  }) async {
    final lastUserPrompt = originalTurns.lastWhere(
      (turn) => turn.role == 'user' && turn.content.trim().isNotEmpty,
      orElse: () => _ChatTurn(role: 'user', content: toolName, time: DateTime.now()),
    );
    final repairPrompt = [
      'MobileCode could not write the generated artifact because the previous provider response did not include one complete HTML document.',
      '',
      'Original user request:',
      lastUserPrompt.content.trim(),
      '',
      'Previous response summary:',
      _compact(originalAnswer, limit: 1600),
      '',
      'Repair contract:',
      '- Return exactly one complete self-contained HTML document.',
      '- Wrap it in a single ```html fenced block.',
      '- Include inline CSS and JavaScript; do not depend on network assets.',
      '- Make it mobile-first and touch-friendly for an Android WebView.',
      '- Do not return capability tables, explanations, Markdown prose, or setup steps.',
      '- Do not mention that you cannot access tools; MobileCode will write and preview the file.',
    ].join('\n');

    final repaired = await _callProvider(
      [_ChatTurn(role: 'user', content: repairPrompt, time: DateTime.now())],
      systemPrompt: [
        systemPrompt,
        '',
        'You are in MobileCode repair mode. Your only valid output is one complete HTML artifact in a ```html fenced block.',
      ].join('\n'),
      maxTokens: 4096,
      responseTimeout: const Duration(minutes: 2),
      trackAgentRequest: true,
      isCancelled: isCancelled,
    );
    if (_extractHtmlDocument(repaired) != null) return repaired;
    throw Exception('Provider responded without a complete ```html block, and the one-shot repair retry also failed. No game file was written.');
  }

  Future<String?> _persistAgentGeneratedArtifact(String toolName, String modelAnswer) async {
    final isWebArtifact = _toolRequiresHtmlArtifact(toolName);
    final slug = switch (toolName) {
      'mobile_coding.generate_snake_preview' => 'agent_snake',
      'mobile_coding.generate_2048_preview' => 'local_tool_2048_from_model',
      'mobile_coding.research_web_preview' => 'agent_research_web_preview',
      'mobile_coding.build_diary_demo' => 'agent_diary',
      _ => 'agent_run',
    };
    final rootDirectory = await _mobileCodeProjectsRootDirectory();
    final projectDirectory = Directory(p.join(rootDirectory.path, slug));
    await projectDirectory.create(recursive: true);
    final actionRunner = ActionRunner(
      workspaceRootPath: rootDirectory.path,
      evidenceStore: _agentEvidenceStore,
    );

    if (isWebArtifact) {
      final html = _extractHtmlDocument(modelAnswer);
      if (html == null) {
        throw Exception('Provider responded, but did not return a complete ```html block. No game file was written.');
      }
      final relativePath = '$slug/index.html';
      final writeResult = await actionRunner.run(ActionSchema(
        actionName: MobileCodeAction.writeFile,
        paramsSummary: 'write generated HTML artifact',
        params: {'path': relativePath, 'content': html, 'overwrite': true},
      ));
      if (!writeResult.success || writeResult.path == null) {
        throw Exception(writeResult.evidence.logs.isEmpty ? 'Failed to write generated HTML artifact.' : writeResult.evidence.logs.first);
      }
      await actionRunner.run(ActionSchema(
        actionName: MobileCodeAction.readFile,
        paramsSummary: 'verify generated HTML artifact',
        params: {'path': relativePath, 'maxBytes': 16 * 1024},
      ));
      await actionRunner.run(ActionSchema(
        actionName: MobileCodeAction.previewHtml,
        paramsSummary: 'prepare generated HTML preview',
        params: {'path': relativePath},
      ));
      return writeResult.path;
    }

    if (toolName.startsWith('mobile_coding.')) {
      final relativePath = '$slug/agent_response.md';
      final writeResult = await actionRunner.run(ActionSchema(
        actionName: MobileCodeAction.writeFile,
        paramsSummary: 'write generated markdown artifact',
        params: {'path': relativePath, 'content': modelAnswer, 'overwrite': true},
      ));
      if (!writeResult.success || writeResult.path == null) {
        throw Exception(writeResult.evidence.logs.isEmpty ? 'Failed to write generated markdown artifact.' : writeResult.evidence.logs.first);
      }
      await actionRunner.run(ActionSchema(
        actionName: MobileCodeAction.readFile,
        paramsSummary: 'verify generated markdown artifact',
        params: {'path': relativePath, 'maxBytes': 16 * 1024},
      ));
      return writeResult.path;
    }
    return null;
  }

  String? _extractHtmlDocument(String modelAnswer) {
    final fenced = RegExp(r'```(?:html|HTML)\s*([\s\S]*?)```').firstMatch(modelAnswer)?.group(1)?.trim();
    if (fenced != null && fenced.contains('<html')) return fenced;
    final lower = modelAnswer.toLowerCase();
    final start = lower.indexOf('<!doctype html');
    if (start != -1) return modelAnswer.substring(start).trim();
    final htmlStart = lower.indexOf('<html');
    if (htmlStart != -1) return modelAnswer.substring(htmlStart).trim();
    return null;
  }

  Future<void> _runAgent() async {
    await _runAgentWithTrace();
  }


  Map<String, dynamic> _requestBody(
    _ApiFlavor flavor,
    List<_ChatTurn> turns, {
    required String systemPrompt,
    int maxTokens = 1024,
    bool stream = false,
  }) {
    final model = widget.model.isEmpty
        ? (flavor == _ApiFlavor.anthropic ? _defaultModel : 'gpt-4o-mini')
        : widget.model;
    final messages = _providerMessages(turns);
    if (flavor == _ApiFlavor.anthropic) {
      return {
        'model': model,
        'system': systemPrompt,
        'max_tokens': maxTokens,
        'stream': stream,
        'messages': messages,
      };
    }
    return {
      'model': model,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        ...messages,
      ],
      'stream': stream,
      if (stream) 'stream_options': {'include_usage': true},
    };
  }

  List<Map<String, dynamic>> _providerMessages(List<_ChatTurn> turns) {
    final usable = turns
        .where((turn) => (turn.role == 'user' || turn.role == 'assistant') && turn.content.trim().isNotEmpty)
        .toList();
    final recent = usable.length > 16 ? usable.sublist(usable.length - 16) : usable;
    final messages = <Map<String, dynamic>>[];

    for (final turn in recent) {
      var role = turn.role;
      if (messages.isEmpty && role == 'assistant') role = 'user';
      if (messages.isNotEmpty && messages.last['role'] == role) {
        messages.last['content'] = '${messages.last['content']}\n\n${turn.content.trim()}';
      } else {
        messages.add({'role': role, 'content': turn.content.trim()});
      }
    }

    return messages.isEmpty
        ? [
            {'role': 'user', 'content': 'Hello'},
          ]
        : messages;
  }

  String _extractAssistantText(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final choices = decoded['choices'];
        if (choices is List && choices.isNotEmpty) {
          final first = choices.first;
          if (first is Map<String, dynamic>) {
            final message = first['message'];
            if (message is Map<String, dynamic>) {
              final content = message['content'];
              if (content is String && content.trim().isNotEmpty) return content.trim();
            }
            final text = first['text'];
            if (text is String && text.trim().isNotEmpty) return text.trim();
          }
        }
        final content = decoded['content'];
        if (content is List && content.isNotEmpty) {
          final parts = <String>[];
          for (final item in content) {
            if (item is Map<String, dynamic>) {
              final text = item['text'];
              if (text is String && text.trim().isNotEmpty) parts.add(text.trim());
            }
          }
          if (parts.isNotEmpty) return parts.join('\n\n');
        }
      }
    } catch (_) {
      // Show raw body when the provider returns a non-standard response.
    }
    return _compact(body);
  }

  String? _extractStreamDelta(Map<String, dynamic> decoded, _ApiFlavor flavor) {
    if (flavor == _ApiFlavor.anthropic) {
      final delta = decoded['delta'];
      if (delta is Map<String, dynamic>) {
        final text = delta['text'];
        if (text is String && text.isNotEmpty) return text;
      }
      final contentBlock = decoded['content_block'];
      if (contentBlock is Map<String, dynamic>) {
        final text = contentBlock['text'];
        if (text is String && text.isNotEmpty) return text;
      }
      final content = decoded['content'];
      if (content is List && content.isNotEmpty) {
        final parts = <String>[];
        for (final item in content) {
          if (item is Map<String, dynamic>) {
            final text = item['text'];
            if (text is String && text.isNotEmpty) parts.add(text);
          }
        }
        if (parts.isNotEmpty) return parts.join('\n\n');
      }
      return null;
    }

    final choices = decoded['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map<String, dynamic>) {
        final delta = first['delta'];
        if (delta is Map<String, dynamic>) {
          final content = delta['content'];
          if (content is String && content.isNotEmpty) return content;
        }
        final message = first['message'];
        if (message is Map<String, dynamic>) {
          final content = message['content'];
          if (content is String && content.isNotEmpty) return content;
        }
      }
    }
    return null;
  }

  String _chatTitle(String prompt) {
    final compact = _compact(prompt, limit: 36);
    return compact.isEmpty ? 'New chat' : compact;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  bool _isNearChatBottom([double threshold = 180]) {
    if (!_chatScrollController.hasClients) return true;
    final position = _chatScrollController.position;
    return (position.maxScrollExtent - position.pixels) <= threshold;
  }

  void _handleChatScroll() {
    if (!_chatScrollController.hasClients) return;
    final nearBottom = _isNearChatBottom();
    final navCount = _conversationNavEntries(_activeSession).length;
    final navIndex = _activeNavIndex(navCount);
    if (nearBottom == _followChatBottom &&
        _showJumpToBottom == !nearBottom &&
        navIndex == _lastNavActiveIndex) {
      return;
    }
    setState(() {
      _followChatBottom = nearBottom;
      _showJumpToBottom = !nearBottom;
      _lastNavActiveIndex = navIndex;
    });
  }

  void _scrollConversationToEnd({bool force = false}) {
    if (!force && _autoScrollScheduled) return;
    if (!force) _autoScrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!force) _autoScrollScheduled = false;
      if (!_chatScrollController.hasClients) return;
      if (!force && !_followChatBottom && !_isNearChatBottom()) return;
      final position = _chatScrollController.position;
      final target = position.maxScrollExtent;
      if ((target - position.pixels).abs() < 2) {
        if (force && mounted) {
          setState(() {
            _followChatBottom = true;
            _showJumpToBottom = false;
          });
        }
        return;
      }
      if (force) {
        _chatScrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      } else {
        // Streaming output can update dozens of times per second. Jumping once per
        // frame avoids stacked animations fighting each other while still keeping
        // the tail visible when the user has not scrolled away.
        _chatScrollController.jumpTo(target);
      }
      if (force && mounted) {
        setState(() {
          _followChatBottom = true;
          _showJumpToBottom = false;
        });
      }
    });
  }

  String _turnNavId(_ChatTurn turn, int index) {
    return '${turn.role}_${turn.time.microsecondsSinceEpoch}_$index';
  }

  GlobalKey _keyForTurn(_ChatTurn turn, int index) {
    return _turnKeys.putIfAbsent(_turnNavId(turn, index), () => GlobalKey());
  }

  List<_ChatNavEntry> _conversationNavEntries(_ChatSession? active) {
    final turns = active?.turns ?? const <_ChatTurn>[];
    final entries = <_ChatNavEntry>[];
    for (var index = 0; index < turns.length; index++) {
      final turn = turns[index];
      final isUser = turn.role == 'user';
      final isKeyResult = turn.role == 'assistant' && _isFinalResultTurn(turn.content);
      final isPublishResult = turn.role == 'assistant' && _isPublishResultTurn(turn.content);
      final isCodeResult = turn.role == 'assistant' && _isCodeResultTurn(turn.content);
      final isBookmark = turn.bookmarked || _isBookmarkedTurn(turn.content);
      if (!isUser && !isKeyResult && !isCodeResult && !isBookmark) continue;
      final summary = _compact(turn.content.replaceAll(RegExp(r'\s+'), ' ').trim(), limit: 72);
      final kind = isBookmark
          ? _ChatNavKind.bookmark
          : isPublishResult
              ? _ChatNavKind.publish
              : isCodeResult
                  ? _ChatNavKind.code
                  : isKeyResult
                      ? _ChatNavKind.result
                      : _ChatNavKind.prompt;
      entries.add(_ChatNavEntry(
        id: _turnNavId(turn, index),
        number: entries.length + 1,
        kind: kind,
        preview: summary.isEmpty
            ? isBookmark
                ? '书签'
                : isPublishResult
                ? '发布成功'
                : isCodeResult
                    ? '代码结果'
                    : isKeyResult
                        ? '关键结果'
                        : '空输入'
            : summary,
      ));
    }
    return entries;
  }

  int? _activeNavIndex(int count) {
    if (count == 0 || !_chatScrollController.hasClients) return null;
    final position = _chatScrollController.position;
    final max = position.maxScrollExtent;
    if (max <= 0) return 0;
    final ratio = (position.pixels / max).clamp(0.0, 1.0);
    final index = (ratio * (count - 1)).round();
    if (index < 0) return 0;
    if (index >= count) return count - 1;
    return index;
  }

  void _showNavPreview(_ChatNavEntry entry) {
    _navPreviewTimer?.cancel();
    setState(() => _navPreview = _ChatNavPreview(entry));
    _navPreviewTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _navPreview = null);
    });
  }

  void _jumpToNavEntry(_ChatNavEntry entry) {
    _showNavPreview(entry);
    final turnContext = _turnKeys[entry.id]?.currentContext;
    if (turnContext != null) {
      Scrollable.ensureVisible(
        turnContext,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
        alignment: 0.12,
      );
      return;
    }
    if (!_chatScrollController.hasClients) return;
    final entries = _conversationNavEntries(_activeSession);
    final index = entries.indexWhere((item) => item.id == entry.id);
    if (index == -1 || entries.length <= 1) return;
    final target = _chatScrollController.position.maxScrollExtent * (index / (entries.length - 1));
    _chatScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  Widget _buildChatHeader() {
    final repoBinding = _repoBinding;
    if (repoBinding == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: _RepoChatBindingBar(
        binding: repoBinding,
        onOpenRepo: () => unawaited(_openExternalUrl(context, repoBinding.repoUrl, label: 'repository', browserOpenMode: widget.browserOpenMode)),
        onOpenPages: repoBinding.pagesUrl == null
            ? null
            : () => unawaited(_openExternalUrl(context, repoBinding.pagesUrl!, label: 'GitHub Pages', browserOpenMode: widget.browserOpenMode)),
        onOpenActions: repoBinding.actionsUrl == null
            ? null
            : () => unawaited(_openExternalUrl(context, repoBinding.actionsUrl!, label: 'GitHub Actions', browserOpenMode: widget.browserOpenMode)),
        onClear: () => setState(() => _repoBinding = null),
      ),
    );
  }

  Future<void> _openArtifactCode(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        _showMessage('Generated code file was not found on this phone.');
        return;
      }
      final code = await file.readAsString();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: _panel,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(10))),
        builder: (context) => _CodeFileSheet(
          path: path,
          code: code,
          onOpenEditor: () => unawaited(_openArtifactInEditor(path, initialContent: code)),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      _showMessage(_compact(error.toString(), limit: 140));
    }
  }

  Future<void> _openArtifactInEditor(String path, {String? initialContent}) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EditorScreen(
          initialFilePath: path,
          initialContent: initialContent,
          fileName: p.basename(path),
        ),
      ),
    );
  }

  Future<void> _previewArtifact(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        _showMessage('Generated web file was not found on this phone.');
        return;
      }
      final html = await file.readAsString();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: _panel,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(10))),
        builder: (context) => _WebPreviewSheet(
          title: 'Generated web preview',
          subtitle: path,
          html: html,
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      _showMessage(_compact(error.toString(), limit: 140));
    }
  }

  Future<void> _openArtifactInBrowser(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        _showMessage('Generated web file was not found on this phone.');
        return;
      }
      final html = await file.readAsString();
      final opened = await _launchHtmlInExternalBrowser(html, browserOpenMode: widget.browserOpenMode);
      if (!mounted) return;
      _showMessage(opened ? 'Opened generated HTML with ${_browserOpenModeLabel(widget.browserOpenMode)}.' : 'No browser accepted this generated HTML.');
    } on Object catch (error) {
      if (!mounted) return;
      _showMessage(_compact(error.toString(), limit: 140));
    }
  }

  Future<void> _copyArtifactPath(String path) async {
    await Clipboard.setData(ClipboardData(text: path));
    if (!mounted) return;
    _showMessage('Phone file path copied.');
  }

  Future<void> _openArtifactFolder(String path) async {
    try {
      final folderPath = _projectDirectoryForArtifact(path);
      final folder = Directory(folderPath);
      if (!await folder.exists()) {
        _showMessage('Project folder was not found on this phone.');
        return;
      }
      final workspaceRoot = await _mobileCodeProjectsRootDirectory();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: _panel,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(10))),
        builder: (context) => _ProjectFolderSheet(
          initialPath: folder.path,
          workspaceRoot: workspaceRoot.path,
          onOpenFile: (filePath) => unawaited(_openArtifactCode(filePath)),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      _showMessage(_compact(error.toString(), limit: 140));
    }
  }

  Future<void> _deployArtifactToGitHubPages(String path) async {
    try {
      final flags = FeatureFlagsService();
      await flags.initialize();
      if (!await flags.isEnabled('github_pages_deploy')) {
        _showMessage('GitHub Pages publishing is disabled in feature flags.');
        return;
      }
      final file = File(path);
      if (!await file.exists()) {
        _showMessage('Generated web file was not found on this phone.');
        return;
      }
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: _panel,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(10))),
        builder: (context) => _GitHubPagesArtifactDeploySheet(
          artifactPath: path,
          onDeployed: _recordPagesDeployment,
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      _showMessage(_compact(error.toString(), limit: 140));
    }
  }

  Future<void> _recordPagesDeployment(_PagesDeploymentSummary summary) async {
    if (!mounted) return;
    final active = _activeSession;
    if (active == null) return;
    final now = DateTime.now();
    final turn = _ChatTurn(
      role: 'assistant',
      content: [
        'GitHub Pages deployment completed.',
        'Web URL: `${summary.url}`',
        'Repository: `${summary.repositoryUrl}`',
        'Code file: `${summary.artifactPath}`',
        'Published at: `${summary.publishedAt.toIso8601String()}`',
        'Pre-publish check: `${summary.readinessSummary}`',
        'Screenshot: `pending`',
      ].join('\n'),
      time: now,
    );
    setState(() {
      _storeSession(active.copyWith(
        updatedAt: now,
        turns: [...active.turns, turn],
      ));
    });
    await _persist();
    _scrollConversationToEnd();
  }

  Future<void> _toggleTurnBookmark(int turnIndex) async {
    final active = _activeSession;
    if (active == null || turnIndex < 0 || turnIndex >= active.turns.length) return;
    final turns = List<_ChatTurn>.of(active.turns);
    final nextTurn = turns[turnIndex].copyWith(bookmarked: !turns[turnIndex].bookmarked);
    turns[turnIndex] = nextTurn;
    final now = DateTime.now();
    setState(() {
      _storeSession(active.copyWith(updatedAt: now, turns: turns));
    });
    _notifySessionsChanged();
    await _persist();
    if (!mounted) return;
    _showMessage(nextTurn.bookmarked ? '已设为书签，可在右侧导航条快速跳转。' : '已取消书签。');
  }

  void _openModelSelectionSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _panel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(10))),
      builder: (context) => _ModelSelectionSheet(
        selected: widget.providerPreset,
        managedPresets: widget.managedProviderPresets,
        onSelect: (preset) {
          Navigator.pop(context);
          widget.onProviderPresetSelected(preset);
        },
      ),
    );
  }

  void _openAgentModeSheet() {
    if (_sending || _agentRunning) return;
    var selectedMode = _agentExecutionMode;
    var selectedPreset = _agentPreset;
    var rrEnabled = _agentModeEnabled;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _panel,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
      builder: (context) => StatefulBuilder(
        builder: (context, modalSetState) => _AgentModeSheet(
          mode: selectedMode,
          preset: selectedPreset,
          rrEnabled: rrEnabled,
          running: _agentRunning || _sending,
          onModeChanged: (mode) {
            setState(() => _agentExecutionMode = mode);
            modalSetState(() => selectedMode = mode);
          },
          onPresetChanged: (preset) {
            setState(() => _agentPreset = preset);
            modalSetState(() => selectedPreset = preset);
          },
          onRrChanged: (value) {
            setState(() => _agentModeEnabled = value);
            modalSetState(() => rrEnabled = value);
          },
        ),
      ),
    );
  }

  Widget _buildConversationBody(_ChatSession? active) {
    final allTurns = active?.turns ?? const <_ChatTurn>[];
    final finalResultTurn = allTurns.isNotEmpty && allTurns.last.role == 'assistant' && _isFinalResultTurn(allTurns.last.content)
        ? allTurns.last
        : null;
    final showAgentTrace = _agentRunning || finalResultTurn != null;
    final conversationTurns = finalResultTurn == null ? allTurns : allTurns.sublist(0, allTurns.length - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Panel(
          padding: const EdgeInsets.all(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 220),
            child: active == null || conversationTurns.isEmpty
                ? const _EmptyChatState()
                : Column(
                    children: [
                      for (var index = 0; index < conversationTurns.length; index++) ...[
                        KeyedSubtree(
                          key: _keyForTurn(conversationTurns[index], index),
                          child: _ChatBubble(
                            turn: conversationTurns[index],
                            onOpenArtifactCode: _openArtifactCode,
                            onPreviewArtifact: _previewArtifact,
                            onOpenArtifactBrowser: _openArtifactInBrowser,
                            onDeployArtifactPages: _deployArtifactToGitHubPages,
                            onCopyArtifactPath: _copyArtifactPath,
                            onOpenArtifactFolder: _openArtifactFolder,
                            onToggleBookmark: () => unawaited(_toggleTurnBookmark(index)),
                            browserOpenMode: widget.browserOpenMode,
                          ),
                        ),
                        if (index != conversationTurns.length - 1) const SizedBox(height: 10),
                      ],
                    ],
                  ),
          ),
        ),
        if (showAgentTrace && _agentTrace.isNotEmpty) ...[
          const SizedBox(height: 12),
          if (_agentModeEnabled) ...[
            _AgentRecruitmentPanel(
              steps: _agentTrace,
              running: _agentRunning,
              roles: _displayRecruitRoles,
              onOpenRole: _openAgentRoleView,
            ),
            const SizedBox(height: 12),
          ],
          _AgentTracePanel(
            title: _agentRunning ? 'Agent is writing code' : 'Last agent process',
            steps: _agentTrace,
          ),
        ],
        if (!_agentRunning && _activeRunProposal != null && _activeRunProposal!.status == RoleProposalStatus.pending) ...[
          const SizedBox(height: 12),
          _RoleProposalApprovalCard(
            proposal: _activeRunProposal!,
            onSave: () => unawaited(_acceptRoleProposal(_activeRunProposal!)),
            onDismiss: () => unawaited(_dismissRoleProposal(_activeRunProposal!)),
            onEdit: () => unawaited(_editRoleProposal(_activeRunProposal!)),
          ),
        ],
        if (finalResultTurn != null) ...[
          const SizedBox(height: 12),
          _Panel(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.flag_outlined, color: _mint, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text('Agent result', style: TextStyle(color: _text, fontSize: 15, fontWeight: FontWeight.w900)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                KeyedSubtree(
                  key: _keyForTurn(finalResultTurn, allTurns.length - 1),
                  child: _ChatBubble(
                    turn: finalResultTurn,
                    onOpenArtifactCode: _openArtifactCode,
                    onPreviewArtifact: _previewArtifact,
                    onOpenArtifactBrowser: _openArtifactInBrowser,
                    onDeployArtifactPages: _deployArtifactToGitHubPages,
                    onCopyArtifactPath: _copyArtifactPath,
                    onOpenArtifactFolder: _openArtifactFolder,
                    onToggleBookmark: () => unawaited(_toggleTurnBookmark(allTurns.length - 1)),
                    browserOpenMode: widget.browserOpenMode,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildComposer() {
    final voiceActive = _voiceState == VoiceState.listening || _voiceService.isListening;
    return Container(
      decoration: BoxDecoration(
        color: _panel,
        border: const Border(top: BorderSide(color: _line)),
        boxShadow: [
          BoxShadow(
            color: _blue.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 10),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _AgentModeSummaryButton(
                  mode: _agentExecutionMode,
                  preset: _agentPreset,
                  rrEnabled: _agentModeEnabled,
                  running: _agentRunning || _sending,
                  onTap: _openAgentModeSheet,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _TaskDispatchStrip(
                    onPrompt: (prompt, {runAgent = false}) => unawaited(setPromptFromShell(prompt, runAgent: runAgent)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
              decoration: BoxDecoration(
                color: _panelSoft,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _line),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _promptController,
                      minLines: 1,
                      maxLines: 3,
                      textInputAction: TextInputAction.newline,
                      style: const TextStyle(color: _text, fontSize: 14.5, height: 1.35),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _ComposerModelButton(
                    preset: widget.providerPreset,
                    model: widget.model,
                    managed: widget.managedProviderPresets.contains(widget.providerPreset),
                    onTap: _sending || _agentRunning ? null : _openModelSelectionSheet,
                  ),
                  const SizedBox(width: 4),
                  _VoiceInputButton(
                    enabled: !_sending && (!_agentRunning || voiceActive),
                    available: _voiceAvailable,
                    state: _voiceState,
                    onTap: _toggleVoiceInput,
                  ),
                  const SizedBox(width: 4),
                  IconButton.filled(
                    tooltip: _sending ? 'Sending' : 'Send chat',
                    style: IconButton.styleFrom(
                      minimumSize: const Size(42, 42),
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: _sending || _agentRunning ? null : _send,
                    icon: _sending
                        ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send_outlined, size: 20),
                  ),
                  if (_agentRunning) ...[
                    const SizedBox(width: 4),
                    IconButton.outlined(
                      tooltip: _agentStopping ? 'Stopping agent' : 'Pause agent run',
                      style: IconButton.styleFrom(
                        minimumSize: const Size(42, 42),
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: _agentStopping ? null : _cancelAgentRun,
                      icon: _agentStopping
                          ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.pause_circle_outline, size: 20),
                    ),
                  ],
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: _rose, fontSize: 12, height: 1.35),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final flavor = _detectApiFlavor(widget.baseUrl, widget.model);
    final active = _activeSession;
    final navEntries = _conversationNavEntries(active);
    if (_loading) {
      return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
    }
    if (widget.embedded) {
      return Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                SingleChildScrollView(
                  controller: _chatScrollController,
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(0, 2, 0, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildChatHeader(),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _buildConversationBody(active),
                      ),
                    ],
                  ),
                ),
                if (_showJumpToBottom)
                  Positioned(
                    right: 18,
                    bottom: 14,
                    child: _JumpToBottomButton(
                      onTap: () => _scrollConversationToEnd(force: true),
                    ),
                  ),
                if (navEntries.length >= 2)
                  Positioned(
                    right: 4,
                    top: 36,
                    bottom: 76,
                    child: _ConversationMinimapRail(
                      entries: navEntries,
                      activeIndex: _activeNavIndex(navEntries.length),
                      onTap: _jumpToNavEntry,
                      onPreview: _showNavPreview,
                    ),
                  ),
                if (_navPreview != null)
                  Positioned(
                    right: 34,
                    top: 70,
                    child: _ConversationMinimapPreview(entry: _navPreview!.entry),
                  ),
              ],
            ),
          ),
          _buildComposer(),
        ],
      );
    }
    return _SheetScaffold(
      icon: Icons.forum_outlined,
      title: 'AI Chat',
      subtitle: _chatEndpointLabel(widget.baseUrl, flavor),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildChatHeader(),
          const SizedBox(height: 12),
          _buildConversationBody(active),
          const SizedBox(height: 12),
          _buildComposer(),
        ],
      ),
    );
  }
}

class _JumpToBottomButton extends StatelessWidget {
  const _JumpToBottomButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _panel,
      elevation: 10,
      shadowColor: _blue.withOpacity(0.25),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: _blue.withOpacity(0.35)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.keyboard_arrow_down_outlined, color: _blue, size: 18),
              SizedBox(width: 4),
              Text('到底部', style: TextStyle(color: _text, fontSize: 12, fontWeight: FontWeight.w900)),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ChatNavKind { prompt, result, code, publish, bookmark }

class _ChatNavEntry {
  const _ChatNavEntry({
    required this.id,
    required this.number,
    required this.kind,
    required this.preview,
  });

  final String id;
  final int number;
  final _ChatNavKind kind;
  final String preview;

  bool get isKeyResult =>
      kind == _ChatNavKind.result || kind == _ChatNavKind.code || kind == _ChatNavKind.publish;
}

class _ChatNavPreview {
  const _ChatNavPreview(this.entry);

  final _ChatNavEntry entry;
}

class _ConversationMinimapRail extends StatelessWidget {
  const _ConversationMinimapRail({
    required this.entries,
    required this.activeIndex,
    required this.onTap,
    required this.onPreview,
  });

  final List<_ChatNavEntry> entries;
  final int? activeIndex;
  final ValueChanged<_ChatNavEntry> onTap;
  final ValueChanged<_ChatNavEntry> onPreview;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxHeight = constraints.maxHeight.isFinite ? constraints.maxHeight : 260.0;
          final itemHeight = entries.isEmpty ? 8.0 : (maxHeight / entries.length).clamp(4.0, 12.0).toDouble();
          return Container(
            width: 24,
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var index = 0; index < entries.length; index++)
                  _ConversationMinimapItem(
                    entry: entries[index],
                    active: index == activeIndex,
                    height: itemHeight,
                    compact: itemHeight < 7,
                    onTap: onTap,
                    onPreview: onPreview,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ConversationMinimapItem extends StatelessWidget {
  const _ConversationMinimapItem({
    required this.entry,
    required this.active,
    required this.height,
    required this.compact,
    required this.onTap,
    required this.onPreview,
  });

  final _ChatNavEntry entry;
  final bool active;
  final double height;
  final bool compact;
  final ValueChanged<_ChatNavEntry> onTap;
  final ValueChanged<_ChatNavEntry> onPreview;

  @override
  Widget build(BuildContext context) {
    final baseColor = switch (entry.kind) {
      _ChatNavKind.result => _mint,
      _ChatNavKind.code => _violet,
      _ChatNavKind.publish => _cyan,
      _ChatNavKind.bookmark => _amber,
      _ChatNavKind.prompt => _line,
    };
    final color = active ? _blue : baseColor;
    return MouseRegion(
      onEnter: (_) => onPreview(entry),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => onTap(entry),
        onLongPress: () => onPreview(entry),
        child: SizedBox(
          width: 24,
          height: height,
          child: Align(
            alignment: Alignment.centerRight,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: active ? 21 : entry.isKeyResult ? 17 : (compact ? 8 : 12),
              height: active ? 3.5 : entry.isKeyResult ? 3 : (compact ? 2 : 2.5),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(999),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: _blue.withOpacity(0.24),
                          blurRadius: 8,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConversationMinimapPreview extends StatelessWidget {
  const _ConversationMinimapPreview({required this.entry});

  final _ChatNavEntry entry;

  @override
  Widget build(BuildContext context) {
    final markerColor = switch (entry.kind) {
      _ChatNavKind.publish => _cyan,
      _ChatNavKind.code => _violet,
      _ChatNavKind.result => _mint,
      _ChatNavKind.bookmark => _amber,
      _ChatNavKind.prompt => _blue,
    };
    final markerLabel = switch (entry.kind) {
      _ChatNavKind.publish => '发布 ${entry.number}',
      _ChatNavKind.code => '代码 ${entry.number}',
      _ChatNavKind.result => '结果 ${entry.number}',
      _ChatNavKind.bookmark => '书签 ${entry.number}',
      _ChatNavKind.prompt => '#${entry.number}',
    };
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 230,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _line),
          boxShadow: [
            BoxShadow(
              color: _blue.withOpacity(0.12),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: markerColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                markerLabel,
                style: TextStyle(color: markerColor, fontSize: 12, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              entry.preview,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _text, fontSize: 12.5, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatSessionChip extends StatelessWidget {
  const _ChatSessionChip({
    required this.session,
    required this.selected,
    required this.onTap,
  });

  final _ChatSession session;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? _mint : _line;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? _mint.withOpacity(0.12) : _panelSoft,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(selected ? 0.70 : 1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              session.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: selected ? _text : _muted, fontWeight: FontWeight.w800, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              _sessionTurnLabel(session),
              style: TextStyle(color: selected ? _mint : _faint, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _RepoChatBindingBar extends StatelessWidget {
  const _RepoChatBindingBar({
    required this.binding,
    required this.onOpenRepo,
    required this.onOpenPages,
    required this.onOpenActions,
    required this.onClear,
  });

  final GitHubRepoChatRequest binding;
  final VoidCallback onOpenRepo;
  final VoidCallback? onOpenPages;
  final VoidCallback? onOpenActions;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final workspacePath = binding.workspacePath;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _blue.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _blue.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_tree_outlined, color: _blue, size: 17),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  binding.repoFullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _text, fontSize: 12, fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                tooltip: 'Clear repo binding',
                visualDensity: VisualDensity.compact,
                onPressed: onClear,
                icon: const Icon(Icons.close_outlined, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _RepoBindingChip(icon: Icons.folder_open_outlined, label: binding.workspaceMode, color: _mint),
              if (workspacePath != null) _RepoBindingChip(icon: Icons.phone_android_outlined, label: 'On phone', color: _cyan),
              _RepoBindingAction(icon: Icons.open_in_new_outlined, label: 'Repo', onTap: onOpenRepo, color: _violet),
              _RepoBindingAction(icon: Icons.web_outlined, label: 'Pages', onTap: onOpenPages, color: _mint),
              _RepoBindingAction(icon: Icons.play_circle_outline, label: 'Actions', onTap: onOpenActions, color: _blue),
            ],
          ),
          if (workspacePath != null) ...[
            const SizedBox(height: 6),
            Text(
              workspacePath,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _faint, fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }
}

class _RepoBindingChip extends StatelessWidget {
  const _RepoBindingChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _RepoBindingAction extends StatelessWidget {
  const _RepoBindingAction({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: _RepoBindingChip(icon: icon, label: label, color: color),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.turn,
    required this.onOpenArtifactCode,
    required this.onPreviewArtifact,
    required this.onOpenArtifactBrowser,
    required this.onDeployArtifactPages,
    required this.onCopyArtifactPath,
    required this.onOpenArtifactFolder,
    required this.onToggleBookmark,
    required this.browserOpenMode,
  });

  final _ChatTurn turn;
  final ValueChanged<String> onOpenArtifactCode;
  final ValueChanged<String> onPreviewArtifact;
  final ValueChanged<String> onOpenArtifactBrowser;
  final ValueChanged<String> onDeployArtifactPages;
  final ValueChanged<String> onCopyArtifactPath;
  final ValueChanged<String> onOpenArtifactFolder;
  final VoidCallback onToggleBookmark;
  final String browserOpenMode;

  @override
  Widget build(BuildContext context) {
    final isUser = turn.role == 'user';
    final color = isUser ? _cyan : _mint;
    final published = isUser ? null : _pagesDeploymentFromContent(turn.content, turn.time);
    final artifactPath = isUser ? null : _artifactPathFromContent(turn.content);
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPress: onToggleBookmark,
        child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * (isUser ? 0.78 : 0.92)),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUser ? _blue.withOpacity(0.11) : _mint.withOpacity(0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.30)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isUser ? 'You' : 'MobileCode',
                  style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900),
                ),
                if (turn.bookmarked) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.bookmark_rounded, color: _amber, size: 14),
                ],
              ],
            ),
            const SizedBox(height: 6),
            if (published != null)
              _PublishedWorkCard(
                info: published,
                onOpenPages: () => unawaited(_openExternalUrl(context, published.pagesUrl, label: 'Pages URL', browserOpenMode: browserOpenMode)),
                onOpenRepo: published.repositoryUrl.isEmpty ? null : () => unawaited(_openExternalUrl(context, published.repositoryUrl, label: 'repository', browserOpenMode: browserOpenMode)),
                onOpenCode: () => onOpenArtifactCode(published.artifactPath),
                onRedeploy: () => onDeployArtifactPages(published.artifactPath),
                onCopyPath: () => onCopyArtifactPath(published.artifactPath),
                onOpenFolder: () => onOpenArtifactFolder(published.artifactPath),
              )
            else if (artifactPath != null) ...[
              _GeneratedArtifactActions(
                path: artifactPath,
                onOpenCode: () => onOpenArtifactCode(artifactPath),
                onPreview: _isWebArtifactPath(artifactPath) ? () => onPreviewArtifact(artifactPath) : null,
                onOpenBrowser: _isWebArtifactPath(artifactPath) ? () => onOpenArtifactBrowser(artifactPath) : null,
                onDeployPages: _isWebArtifactPath(artifactPath) ? () => onDeployArtifactPages(artifactPath) : null,
                onCopyPath: () => onCopyArtifactPath(artifactPath),
                onOpenFolder: () => onOpenArtifactFolder(artifactPath),
              ),
              const SizedBox(height: 10),
              _AssistantContentView(content: turn.content, isUser: isUser),
            ] else
              _AssistantContentView(content: turn.content, isUser: isUser),
          ],
        ),
        ),
      ),
    );
  }
}

class _AssistantContentView extends StatefulWidget {
  const _AssistantContentView({
    required this.content,
    required this.isUser,
  });

  final String content;
  final bool isUser;

  @override
  State<_AssistantContentView> createState() => _AssistantContentViewState();
}

class _AssistantContentViewState extends State<_AssistantContentView> {
  bool _expanded = false;
  final ScrollController _codeScrollController = ScrollController();

  @override
  void dispose() {
    _codeScrollController.dispose();
    super.dispose();
  }

  bool get _shouldCollapse {
    if (widget.isUser) return false;
    return widget.content.length > 1800 ||
        widget.content.contains('```') ||
        widget.content.contains('<!DOCTYPE html') ||
        widget.content.contains('<html');
  }

  @override
  Widget build(BuildContext context) {
    final shouldCollapse = _shouldCollapse;
    final content = shouldCollapse && !_expanded ? _compact(widget.content, limit: 900) : widget.content;
    final text = SelectableText(
      content,
      style: const TextStyle(color: _text, height: 1.42, fontSize: 13),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (shouldCollapse && _expanded)
          Container(
            constraints: const BoxConstraints(maxHeight: 360),
            decoration: BoxDecoration(
              color: _bg.withOpacity(0.28),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _line),
            ),
            child: Scrollbar(
              controller: _codeScrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _codeScrollController,
                padding: const EdgeInsets.all(10),
                child: text,
              ),
            ),
          )
        else
          text,
        if (shouldCollapse) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(_expanded ? Icons.unfold_less_outlined : Icons.unfold_more_outlined, size: 16),
                label: Text(_expanded ? '折叠代码/全文' : '展开代码/全文'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _blue,
                  side: BorderSide(color: _blue.withOpacity(0.35)),
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  unawaited(Clipboard.setData(ClipboardData(text: widget.content)));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已复制完整代码/全文')),
                  );
                },
                icon: const Icon(Icons.copy_all_outlined, size: 16),
                label: const Text('复制全文'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _mint,
                  side: BorderSide(color: _mint.withOpacity(0.35)),
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ),
              if (_expanded)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '完整查看请使用上方“代码文件 / 网页预览 / 浏览器打开”。',
                    style: TextStyle(color: _faint, fontSize: 11.5, height: 1.3),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _GeneratedArtifactActions extends StatelessWidget {
  const _GeneratedArtifactActions({
    required this.path,
    required this.onOpenCode,
    required this.onPreview,
    required this.onOpenBrowser,
    required this.onDeployPages,
    required this.onCopyPath,
    required this.onOpenFolder,
  });

  final String path;
  final VoidCallback onOpenCode;
  final VoidCallback? onPreview;
  final VoidCallback? onOpenBrowser;
  final VoidCallback? onDeployPages;
  final VoidCallback onCopyPath;
  final VoidCallback onOpenFolder;

  @override
  Widget build(BuildContext context) {
    final projectPath = _projectDirectoryForArtifact(path);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.folder_open_outlined, color: _mint, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Generated artifact on this phone',
                  style: const TextStyle(color: _text, fontSize: 12, fontWeight: FontWeight.w900),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              FutureBuilder<String?>(
                future: _findGitRootForPath(projectPath),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2));
                  }
                  if (snapshot.data == null) return const SizedBox.shrink();
                  return const _Pill(label: 'Git', icon: Icons.account_tree_outlined, color: _mint);
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(
            path,
            maxLines: 2,
            style: const TextStyle(color: _muted, fontSize: 11, height: 1.25),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.folder_copy_outlined, color: _faint, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Project folder: ${p.basename(projectPath)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _faint, fontSize: 11, height: 1.25),
                ),
              ),
            ],
          ),
          if (onDeployPages != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: onDeployPages,
                icon: const _GitHubMarkIcon(size: 17, color: Colors.white),
                label: const Text(
                  '发布 GitHub Pages',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MiniArtifactButton(icon: Icons.code_outlined, label: '代码文件', onTap: onOpenCode, color: _blue),
              if (onPreview != null) _MiniArtifactButton(icon: Icons.preview_outlined, label: '网页预览', onTap: onPreview!, color: _violet),
              if (onOpenBrowser != null) _MiniArtifactButton(icon: Icons.open_in_browser_outlined, label: '浏览器打开', onTap: onOpenBrowser!, color: _amber),
              _MiniArtifactButton(icon: Icons.folder_open_outlined, label: '工程文件夹', onTap: onOpenFolder, color: _mint),
              _MiniArtifactButton(icon: Icons.copy_outlined, label: '复制路径', onTap: onCopyPath, color: _cyan),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniArtifactButton extends StatelessWidget {
  const _MiniArtifactButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
    this.leading,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.35)),
        visualDensity: VisualDensity.compact,
      ),
      onPressed: onTap,
      icon: leading ?? Icon(icon, size: 15),
      label: Text(label),
    );
  }
}

class _GitHubMarkIcon extends StatelessWidget {
  const _GitHubMarkIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/icons/github-mark-24.svg',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      semanticsLabel: 'GitHub',
    );
  }
}

class _ProjectFolderSheet extends StatefulWidget {
  const _ProjectFolderSheet({
    required this.initialPath,
    required this.workspaceRoot,
    required this.onOpenFile,
  });

  final String initialPath;
  final String workspaceRoot;
  final ValueChanged<String> onOpenFile;

  @override
  State<_ProjectFolderSheet> createState() => _ProjectFolderSheetState();
}

class _ProjectFolderSheetState extends State<_ProjectFolderSheet> {
  late String _currentPath;
  late Future<_ProjectFolderSnapshot> _snapshot;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.initialPath;
    _snapshot = _readFolder(_currentPath);
  }

  Future<_ProjectFolderSnapshot> _readFolder(String path) async {
    final directory = Directory(path);
    if (!await directory.exists()) {
      throw Exception('Folder does not exist: $path');
    }
    final entries = await directory.list().toList();
    entries.sort((a, b) {
      final aDir = FileSystemEntity.isDirectorySync(a.path);
      final bDir = FileSystemEntity.isDirectorySync(b.path);
      if (aDir != bDir) return aDir ? -1 : 1;
      return p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
    });
    return _ProjectFolderSnapshot(
      path: directory.path,
      gitRoot: await _findGitRootForPath(directory.path),
      entries: entries.take(120).toList(growable: false),
    );
  }

  void _openFolder(String path) {
    setState(() {
      _currentPath = path;
      _snapshot = _readFolder(path);
    });
  }

  void _openParent() {
    final parent = Directory(_currentPath).parent.path;
    if (!_canOpenParent(_currentPath, parent)) return;
    _openFolder(parent);
  }

  bool _canOpenParent(String currentPath, String parentPath) {
    if (p.equals(parentPath, currentPath)) return false;
    return p.equals(parentPath, widget.workspaceRoot) || p.isWithin(widget.workspaceRoot, parentPath);
  }

  Future<void> _copyPath(String path, String label) async {
    await Clipboard.setData(ClipboardData(text: path));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label copied.')));
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      icon: Icons.folder_open_outlined,
      title: 'Project files',
      subtitle: _currentPath,
      child: FutureBuilder<_ProjectFolderSnapshot>(
        future: _snapshot,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            return _Panel(
              child: Text(
                _compact(snapshot.error.toString(), limit: 220),
                style: const TextStyle(color: _rose, height: 1.35),
              ),
            );
          }
          final data = snapshot.requireData;
          final parentPath = Directory(data.path).parent.path;
          final canGoUp = _canOpenParent(data.path, parentPath);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Panel(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.home_work_outlined, color: _blue, size: 18),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'MobileCode workspace',
                            style: TextStyle(color: _text, fontWeight: FontWeight.w900),
                          ),
                        ),
                        if (data.gitRoot != null) const _Pill(label: 'Git repository', icon: Icons.account_tree_outlined, color: _mint),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      data.path,
                      style: const TextStyle(color: _muted, fontSize: 12, height: 1.35),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Workspace relative: ${_workspaceRelativePath(data.path, widget.workspaceRoot)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _faint, fontSize: 11, height: 1.3),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: canGoUp ? _openParent : null,
                          icon: const Icon(Icons.arrow_upward_outlined, size: 16),
                          label: const Text('上一级'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => unawaited(_copyPath(data.path, 'Folder path')),
                          icon: const Icon(Icons.copy_outlined, size: 16),
                          label: const Text('复制文件夹路径'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (data.entries.isEmpty)
                const _Panel(
                  child: Text('This project folder is empty.', style: TextStyle(color: _muted)),
                )
              else
                _Panel(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var index = 0; index < data.entries.length; index++) ...[
                        _ProjectFileRow(
                          entity: data.entries[index],
                          onOpenFolder: _openFolder,
                          onOpenFile: (path) {
                            Navigator.of(context).pop();
                            widget.onOpenFile(path);
                          },
                        ),
                        if (index != data.entries.length - 1) const Divider(height: 1, color: _line),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ProjectFolderSnapshot {
  const _ProjectFolderSnapshot({
    required this.path,
    required this.gitRoot,
    required this.entries,
  });

  final String path;
  final String? gitRoot;
  final List<FileSystemEntity> entries;
}

class _ProjectFileRow extends StatelessWidget {
  const _ProjectFileRow({
    required this.entity,
    required this.onOpenFolder,
    required this.onOpenFile,
  });

  final FileSystemEntity entity;
  final ValueChanged<String> onOpenFolder;
  final ValueChanged<String> onOpenFile;

  @override
  Widget build(BuildContext context) {
    final isDirectory = FileSystemEntity.isDirectorySync(entity.path);
    final name = p.basename(entity.path);
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: Icon(
        isDirectory ? Icons.folder_outlined : Icons.description_outlined,
        color: isDirectory ? _amber : _cyan,
      ),
      title: Text(
        name.isEmpty ? entity.path : name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: _text, fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        entity.path,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: _faint, fontSize: 11),
      ),
      trailing: Icon(
        isDirectory ? Icons.chevron_right_outlined : Icons.open_in_new_outlined,
        color: _faint,
        size: 18,
      ),
      onTap: () => isDirectory ? onOpenFolder(entity.path) : onOpenFile(entity.path),
    );
  }
}

class _EmptyChatState extends StatelessWidget {
  const _EmptyChatState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, color: _faint, size: 36),
            SizedBox(height: 10),
            Text('No messages yet', style: TextStyle(color: _text, fontWeight: FontWeight.w800)),
            SizedBox(height: 4),
            Text(
              'Use Send Chat for normal memory, or Run Agent to show the live coding/tool process.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentModeToggle extends StatelessWidget {
  const _AgentModeToggle({
    required this.enabled,
    required this.running,
    required this.onChanged,
  });

  final bool enabled;
  final bool running;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? _violet : _faint;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(enabled ? 0.10 : 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(enabled ? 0.34 : 0.18)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: enabled
                ? SvgPicture.asset(
                    _rrModeAvatarAsset,
                    fit: BoxFit.contain,
                    placeholderBuilder: (_) => Icon(Icons.psychology_alt_outlined, color: color, size: 18),
                  )
                : Icon(Icons.groups_2_outlined, color: color, size: 20),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  enabled ? 'RR mode on' : 'RR mode off',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _text, fontSize: 12, fontWeight: FontWeight.w900),
                ),
                Text(
                  enabled ? 'One run, multiple role personalities' : 'Plain chat surface',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 10.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(
            value: enabled,
            onChanged: running ? null : onChanged,
            activeColor: _violet,
          ),
        ],
      ),
    );
  }
}

class _AgentModeSummaryButton extends StatelessWidget {
  const _AgentModeSummaryButton({
    required this.mode,
    required this.preset,
    required this.rrEnabled,
    required this.running,
    required this.onTap,
  });

  final AgentExecutionMode mode;
  final AgentPreset preset;
  final bool rrEnabled;
  final bool running;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = mode == AgentExecutionMode.agentLoop ? _violet : _mint;
    final detail = mode == AgentExecutionMode.agentLoop ? '${preset.label} · 角色协作' : 'Single-shot';
    return Tooltip(
      message: '打开模式面板：选择执行模式、Agent preset 和 RR 角色增强。',
      child: InkWell(
        onTap: running ? null : onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 38,
          constraints: const BoxConstraints(maxWidth: 172),
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withOpacity(0.34)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                mode == AgentExecutionMode.agentLoop ? Icons.account_tree_outlined : Icons.bolt_outlined,
                color: color,
                size: 16,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '模式',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: _faint, fontSize: 9.5, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _text, fontSize: 11.5, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
              if (rrEnabled) ...[
                const SizedBox(width: 5),
                const _TinyBadge(label: 'RR', color: _violet),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AgentModeSheet extends StatelessWidget {
  const _AgentModeSheet({
    required this.mode,
    required this.preset,
    required this.rrEnabled,
    required this.running,
    required this.onModeChanged,
    required this.onPresetChanged,
    required this.onRrChanged,
  });

  final AgentExecutionMode mode;
  final AgentPreset preset;
  final bool rrEnabled;
  final bool running;
  final ValueChanged<AgentExecutionMode> onModeChanged;
  final ValueChanged<AgentPreset> onPresetChanged;
  final ValueChanged<bool> onRrChanged;

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      icon: Icons.tune_outlined,
      title: '模式与协作',
      subtitle: '模式决定执行方式；任务派发只负责把预置请求送进当前模式。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Panel(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('执行模式', style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 14)),
                const SizedBox(height: 9),
                _AgentExecutionModeSegment(
                  mode: mode,
                  running: running,
                  onChanged: onModeChanged,
                ),
                const SizedBox(height: 10),
                Text(
                  mode == AgentExecutionMode.agentLoop
                      ? 'Agent Loop 会让模型通过 provider-native tool call 自主选择工具，MobileCode 只负责校验、执行、记录 evidence、回传 observation。'
                      : 'Single-shot 是稳定回退路径：模型一次性回答，MobileCode 可提取、保存并预览生成产物。',
                  style: const TextStyle(color: _muted, fontSize: 12, height: 1.35),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (mode == AgentExecutionMode.agentLoop) ...[
            _Panel(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.account_tree_outlined, color: _violet, size: 18),
                      SizedBox(width: 7),
                      Expanded(
                        child: Text('角色协作', style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 14)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Planner -> Builder -> Reviewer -> Repair 在同一条手机执行链路内切换职责，不是并发后台 Agent。每个 preset 只是不同的工具权限和行为策略。',
                    style: TextStyle(color: _muted, fontSize: 12, height: 1.35),
                  ),
                  const SizedBox(height: 10),
                  _AgentPresetStrip(
                    selected: preset,
                    running: running,
                    onChanged: onPresetChanged,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          _Panel(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('RR 角色增强', style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 14)),
                      SizedBox(height: 5),
                      Text(
                        '偏人格/职责上下文增强，不等同于真正多线程子 Agent。',
                        style: TextStyle(color: _muted, fontSize: 12, height: 1.3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _CompactAgentModeToggle(
                  enabled: rrEnabled,
                  running: running,
                  onChanged: onRrChanged,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentExecutionModeSegment extends StatelessWidget {
  const _AgentExecutionModeSegment({
    required this.mode,
    required this.running,
    required this.onChanged,
  });

  final AgentExecutionMode mode;
  final bool running;
  final ValueChanged<AgentExecutionMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _panelSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AgentExecutionModeChip(
            label: 'Single-shot',
            selected: mode == AgentExecutionMode.singleShot,
            enabled: !running,
            color: _mint,
            onTap: () => onChanged(AgentExecutionMode.singleShot),
          ),
          _AgentExecutionModeChip(
            label: 'Agent Loop',
            selected: mode == AgentExecutionMode.agentLoop,
            enabled: !running,
            color: _violet,
            onTap: () => onChanged(AgentExecutionMode.agentLoop),
          ),
        ],
      ),
    );
  }
}

class _AgentExecutionModeChip extends StatelessWidget {
  const _AgentExecutionModeChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled && !selected ? onTap : null,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? _text : _muted,
            fontSize: 11.5,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _AgentPresetStrip extends StatelessWidget {
  const _AgentPresetStrip({
    required this.selected,
    required this.running,
    required this.onChanged,
  });

  final AgentPreset selected;
  final bool running;
  final ValueChanged<AgentPreset> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          const _AgentRoleFlowBadge(),
          const SizedBox(width: 6),
          for (final preset in AgentPreset.values) ...[
            _AgentPresetChip(
              preset: preset,
              selected: preset == selected,
              enabled: !running,
              onTap: () => onChanged(preset),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _AgentRoleFlowBadge extends StatelessWidget {
  const _AgentRoleFlowBadge();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '角色协作：Planner -> Builder -> Reviewer -> Repair，在同一 Agent Loop 内编排，不是并发后台线程。',
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: _violet.withOpacity(0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _violet.withOpacity(0.30)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_tree_outlined, color: _violet, size: 15),
            SizedBox(width: 5),
            Text(
              '角色协作',
              style: TextStyle(color: _text, fontSize: 11.5, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentPresetChip extends StatelessWidget {
  const _AgentPresetChip({
    required this.preset,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final AgentPreset preset;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = switch (preset) {
      AgentPreset.autoAgent => _violet,
      AgentPreset.builder => _mint,
      AgentPreset.researchBuilder => _amber,
      AgentPreset.repair => _cyan,
      AgentPreset.reviewer => _blue,
    };
    return Tooltip(
      message: preset.shortDescription,
      child: InkWell(
        onTap: enabled && !selected ? onTap : null,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected ? color.withOpacity(0.14) : _panelSoft,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withOpacity(selected ? 0.48 : 0.20)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                switch (preset) {
                  AgentPreset.autoAgent => Icons.auto_awesome_outlined,
                  AgentPreset.builder => Icons.construction_outlined,
                  AgentPreset.researchBuilder => Icons.travel_explore_outlined,
                  AgentPreset.repair => Icons.healing_outlined,
                  AgentPreset.reviewer => Icons.fact_check_outlined,
                },
                color: color,
                size: 15,
              ),
              const SizedBox(width: 5),
              Text(
                preset.label,
                style: TextStyle(color: selected ? _text : _muted, fontSize: 11.5, fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactAgentModeToggle extends StatelessWidget {
  const _CompactAgentModeToggle({
    required this.enabled,
    required this.running,
    required this.onChanged,
  });

  final bool enabled;
  final bool running;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? _violet : _faint;
    return Tooltip(
      message: enabled ? 'RR mode on: role personalities guide the run' : 'Plain chat mode',
      child: InkWell(
        onTap: running ? null : () => onChanged(!enabled),
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: color.withOpacity(enabled ? 0.12 : 0.06),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withOpacity(enabled ? 0.42 : 0.20)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (enabled) ...[
                Icon(Icons.groups_2_outlined, color: color, size: 16),
                const SizedBox(width: 5),
              ],
              Text(
                enabled ? 'RR' : 'Chat',
                style: TextStyle(color: enabled ? _text : _muted, fontSize: 11.5, fontWeight: FontWeight.w900),
              ),
              const SizedBox(width: 5),
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: running
                      ? _amber
                      : enabled
                          ? _violet
                          : _line,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskDispatchStrip extends StatelessWidget {
  const _TaskDispatchStrip({required this.onPrompt});

  final void Function(String prompt, {bool runAgent}) onPrompt;

  @override
  Widget build(BuildContext context) {
    const prompts = [
      _PromptShortcutData(
        label: '贪吃蛇',
        icon: Icons.videogame_asset_outlined,
        prompt: '帮我在手机端创建一个可运行的贪吃蛇网页小游戏，生成 index.html、展示写代码过程，并用 WebView 预览。',
        color: _mint,
      ),
      _PromptShortcutData(
        label: '2048',
        icon: Icons.grid_4x4_outlined,
        prompt: '帮我创建一个 2048 网页小游戏，保存为 index.html，并打开本地 WebView 预览。',
        color: _cyan,
      ),
      _PromptShortcutData(
        label: 'GitHub',
        icon: Icons.hub_outlined,
        prompt: '测试 GitHub token 与 Harzva/mobilecode 仓库是否联通，并说明失败原因。',
        color: _violet,
      ),
      _PromptShortcutData(
        label: '复杂验收',
        icon: Icons.travel_explore_outlined,
        prompt: '复杂验收：请在手机本地生成一个动物森友会风格 3D 小岛 HTML 展示页。可用工具包括 list_files、find_files、grep_files、web_search、fetch_url、write_file、read_file、move_file、apply_patch、preview_html、preview_snapshot、report_result；请根据观察结果自主选择最小安全步骤，必要时搜索/读取公开 HTTPS 参考，最后报告有用的 refId、evidenceId、预览路径和快照结果。',
        color: _amber,
      ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          const _TaskDispatchLabel(),
          const SizedBox(width: 8),
          for (final item in prompts) ...[
            _PromptShortcutChip(item: item, onTap: () => onPrompt(item.prompt, runAgent: true)),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _TaskDispatchLabel extends StatelessWidget {
  const _TaskDispatchLabel();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: _panelSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _line),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.rocket_launch_outlined, color: _amber, size: 15),
          SizedBox(width: 5),
          Text(
            '任务派发',
            style: TextStyle(color: _text, fontSize: 11.5, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _PromptLaunchPanel extends StatelessWidget {
  const _PromptLaunchPanel({required this.onPrompt});

  final Future<void> Function(String prompt, {bool runAgent}) onPrompt;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.bolt_outlined, color: _mint, size: 19),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'One-tap coding prompts',
                  style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '这些按钮会回到聊天页并填入任务，让 agent 以“思考 -> 工具调用 -> 写文件 -> 预览”的方式执行。',
            style: TextStyle(color: _muted, fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ActionChipButton(
                icon: Icons.videogame_asset_outlined,
                label: '贪吃蛇游戏',
                color: _mint,
                onTap: () => onPrompt('帮我在手机端创建一个可运行的贪吃蛇网页小游戏，生成 index.html、展示写代码过程，并用 WebView 预览。', runAgent: true),
              ),
              _ActionChipButton(
                icon: Icons.grid_4x4_outlined,
                label: '2048 Demo',
                color: _cyan,
                onTap: () => onPrompt('帮我创建一个 2048 网页小游戏，保存为 index.html，并打开本地 WebView 预览。', runAgent: true),
              ),
              _ActionChipButton(
                icon: Icons.edit_note_outlined,
                label: '日记 App',
                color: _amber,
                onTap: () => onPrompt('帮我做一个最小日记 App：本地保存、列表、编辑、删除和空状态都要能在 APK 里体验。'),
              ),
              _ActionChipButton(
                icon: Icons.travel_explore_outlined,
                label: '复杂 Harness 验收',
                color: _violet,
                onTap: () => onPrompt('复杂验收：请在手机本地生成一个动物森友会风格 3D 小岛 HTML 展示页。可用工具包括 list_files、find_files、grep_files、web_search、fetch_url、write_file、read_file、move_file、apply_patch、preview_html、preview_snapshot、report_result；请根据观察结果自主选择最小安全步骤，必要时搜索/读取公开 HTTPS 参考，最后报告有用的 refId、evidenceId、预览路径和快照结果。', runAgent: true),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ManagementSurfacePanel extends StatelessWidget {
  const _ManagementSurfacePanel({
    required this.onOpenAgent,
    required this.onOpenRoles,
    required this.onOpenSkills,
    required this.onOpenMcp,
    required this.onOpenMemory,
    required this.onOpenHooks,
    required this.onOpenUsage,
    required this.onOpenDevice,
  });

  final VoidCallback onOpenAgent;
  final VoidCallback onOpenRoles;
  final VoidCallback onOpenSkills;
  final VoidCallback onOpenMcp;
  final VoidCallback onOpenMemory;
  final VoidCallback onOpenHooks;
  final VoidCallback onOpenUsage;
  final VoidCallback onOpenDevice;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.dashboard_customize_outlined, color: _cyan, size: 19),
              SizedBox(width: 8),
              Expanded(
                child: Text('MobileCode control center', style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 15)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MiniArtifactButton(icon: Icons.psychology_alt_outlined, label: 'Agent', onTap: onOpenAgent, color: _violet),
              _MiniArtifactButton(icon: Icons.badge_outlined, label: 'Roles', onTap: onOpenRoles, color: _blue),
              _MiniArtifactButton(icon: Icons.extension_outlined, label: 'Skills', onTap: onOpenSkills, color: _mint),
              _MiniArtifactButton(icon: Icons.account_tree_outlined, label: 'MCP', onTap: onOpenMcp, color: _cyan),
              _MiniArtifactButton(icon: Icons.memory_outlined, label: 'Memory', onTap: onOpenMemory, color: _amber),
              _MiniArtifactButton(icon: Icons.cable_outlined, label: 'Hooks', onTap: onOpenHooks, color: _violet),
              _MiniArtifactButton(icon: Icons.token_outlined, label: 'Usage', onTap: onOpenUsage, color: _rose),
              _MiniArtifactButton(icon: Icons.speed_outlined, label: 'Device', onTap: onOpenDevice, color: _lime),
            ],
          ),
        ],
      ),
    );
  }
}

class _PromptShortcutData {
  const _PromptShortcutData({
    required this.label,
    required this.icon,
    required this.prompt,
    required this.color,
  });

  final String label;
  final IconData icon;
  final String prompt;
  final Color color;
}

class _PromptShortcutChip extends StatelessWidget {
  const _PromptShortcutChip({
    required this.item,
    required this.onTap,
  });

  final _PromptShortcutData item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: item.color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: item.color.withOpacity(0.34)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(item.icon, color: item.color, size: 15),
            const SizedBox(width: 5),
            Text(item.label, style: const TextStyle(color: _text, fontSize: 11.5, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _ActionChipButton extends StatelessWidget {
  const _ActionChipButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, color: color, size: 17),
      label: Text(label),
      side: BorderSide(color: color.withOpacity(0.35)),
      backgroundColor: color.withOpacity(0.10),
      labelStyle: const TextStyle(color: _text, fontWeight: FontWeight.w800),
      onPressed: onTap,
    );
  }
}

class _ComposerModelButton extends StatelessWidget {
  const _ComposerModelButton({
    required this.preset,
    required this.model,
    required this.managed,
    required this.onTap,
  });

  final _ProviderPreset preset;
  final String model;
  final bool managed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = preset == _ProviderPreset.deepSeek ? _violet : _blue;
    final label = _providerPresetLabel(preset);
    final modelLabel = model.trim().isEmpty ? _providerPresetModel(preset) : model.trim();
    return Tooltip(
      message: managed ? '$label built-in model: $modelLabel' : '$label custom model: $modelLabel',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 42,
          constraints: const BoxConstraints(minWidth: 78, maxWidth: 122),
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: color.withOpacity(managed ? 0.14 : 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(managed ? 0.34 : 0.18)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(preset == _ProviderPreset.deepSeek ? Icons.psychology_alt_outlined : Icons.auto_awesome_outlined, color: color, size: 16),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _text, fontSize: 12, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 3),
              Icon(Icons.keyboard_arrow_down_rounded, color: color, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModelSelectionSheet extends StatelessWidget {
  const _ModelSelectionSheet({
    required this.selected,
    required this.managedPresets,
    required this.onSelect,
  });

  final _ProviderPreset selected;
  final List<_ProviderPreset> managedPresets;
  final ValueChanged<_ProviderPreset> onSelect;

  @override
  Widget build(BuildContext context) {
    final choices = const [
      _ProviderPreset.mimo,
      _ProviderPreset.deepSeek,
      _ProviderPreset.openAi,
      _ProviderPreset.anthropic,
      _ProviderPreset.custom,
    ];
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.auto_awesome_outlined, color: _blue, size: 19),
                SizedBox(width: 8),
                Expanded(
                  child: Text('选择模型', style: TextStyle(color: _text, fontSize: 16, fontWeight: FontWeight.w900)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              '内置模型隐藏凭据，用户可以直接体验；Custom 仍然用于粘贴自己的 provider key。',
              style: TextStyle(color: _muted, fontSize: 12, height: 1.35),
            ),
            const SizedBox(height: 12),
            for (final preset in choices) ...[
              _ModelSelectionRow(
                preset: preset,
                selected: selected == preset,
                managed: managedPresets.contains(preset),
                onTap: () => onSelect(preset),
              ),
              if (preset != choices.last) const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _ModelSelectionRow extends StatelessWidget {
  const _ModelSelectionRow({
    required this.preset,
    required this.selected,
    required this.managed,
    required this.onTap,
  });

  final _ProviderPreset preset;
  final bool selected;
  final bool managed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = preset == _ProviderPreset.deepSeek
        ? _violet
        : preset == _ProviderPreset.mimo
            ? _mint
            : _blue;
    final subtitle = switch (preset) {
      _ProviderPreset.mimo => managed ? '内置体验模型，稳定聊天与中文移动开发任务' : '需要构建时配置 Mimo managed key',
      _ProviderPreset.deepSeek => managed ? '内置 DeepSeek v4 Flash，默认更快；Pro 可手动切换' : '推荐接入 DeepSeek v4 key 后用于编码任务',
      _ProviderPreset.openAi => 'OpenAI-compatible，自带 key 时使用',
      _ProviderPreset.anthropic => 'Anthropic-compatible，自带 key 时使用',
      _ProviderPreset.custom => '保留当前自定义 Base URL / Model / API Key',
    };
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.12) : _panelSoft,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? color.withOpacity(0.44) : _line),
        ),
        child: Row(
          children: [
            Icon(
              preset == _ProviderPreset.custom
                  ? Icons.tune_outlined
                  : preset == _ProviderPreset.deepSeek
                      ? Icons.psychology_alt_outlined
                      : Icons.auto_awesome_outlined,
              color: color,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          _providerPresetLabel(preset),
                          style: const TextStyle(color: _text, fontSize: 14, fontWeight: FontWeight.w900),
                        ),
                      ),
                      if (managed) ...[
                        const SizedBox(width: 8),
                        _TinyBadge(label: 'Built-in', color: color),
                      ],
                      if (preset == _ProviderPreset.deepSeek) ...[
                        const SizedBox(width: 6),
                        const _TinyBadge(label: '推荐编码', color: _violet),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(subtitle, style: const TextStyle(color: _muted, fontSize: 11.5, height: 1.25)),
                ],
              ),
            ),
            if (selected) const Icon(Icons.check_circle_outline, color: _mint, size: 20),
          ],
        ),
      ),
    );
  }
}

class _TinyBadge extends StatelessWidget {
  const _TinyBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900)),
    );
  }
}

class _VoiceInputButton extends StatelessWidget {
  const _VoiceInputButton({
    required this.enabled,
    required this.available,
    required this.state,
    required this.onTap,
  });

  final bool enabled;
  final bool available;
  final VoiceState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final listening = state == VoiceState.listening;
    final color = listening
        ? _rose
        : available
            ? _mint
            : _amber;
    return Tooltip(
      message: listening ? 'Stop voice input' : 'Voice input',
      child: SizedBox(
        width: 42,
        height: 42,
        child: FilledButton(
          style: FilledButton.styleFrom(
            padding: EdgeInsets.zero,
            backgroundColor: color.withOpacity(listening ? 0.92 : 0.16),
            foregroundColor: listening ? _bg : color,
            minimumSize: const Size(42, 42),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: enabled ? onTap : null,
          child: Icon(listening ? Icons.stop_rounded : Icons.mic_none_outlined, size: 20),
        ),
      ),
    );
  }
}

class _DraftSheet extends StatefulWidget {
  const _DraftSheet({required this.onCreate});

  final void Function(String name, String language) onCreate;

  @override
  State<_DraftSheet> createState() => _DraftSheetState();
}

class _DraftSheetState extends State<_DraftSheet> {
  final _name = TextEditingController(text: 'lib/screens/new_feature.dart');
  final _language = TextEditingController(text: 'Dart');
  final _content = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _language.dispose();
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      icon: Icons.note_add_outlined,
      title: 'New File Draft',
      subtitle: 'Create a local draft from the editor controller surface.',
      child: Column(
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'File path', prefixIcon: Icon(Icons.description_outlined)),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _language,
            decoration: const InputDecoration(labelText: 'Language', prefixIcon: Icon(Icons.code_outlined)),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _content,
            minLines: 5,
            maxLines: 8,
            decoration: const InputDecoration(labelText: 'Initial content', alignLabelWithHint: true),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                final name = _name.text.trim().isEmpty ? 'untitled.dart' : _name.text.trim();
                final language = _language.text.trim().isEmpty ? 'Text' : _language.text.trim();
                widget.onCreate(name, language);
                Navigator.pop(context);
              },
              icon: const Icon(Icons.add_outlined),
              label: const Text('Create draft'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SnippetSheet extends StatefulWidget {
  const _SnippetSheet({required this.onCreate});

  final void Function(String title, String language) onCreate;

  @override
  State<_SnippetSheet> createState() => _SnippetSheetState();
}

class _SnippetSheetState extends State<_SnippetSheet> {
  final _title = TextEditingController(text: 'API client helper');
  final _language = TextEditingController(text: 'Dart');
  final _code = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _language.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      icon: Icons.data_object_outlined,
      title: 'Snippet Capture',
      subtitle: 'Save reusable code into the snippet surface.',
      child: Column(
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title', prefixIcon: Icon(Icons.label_outline)),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _language,
            decoration: const InputDecoration(labelText: 'Language', prefixIcon: Icon(Icons.code_outlined)),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _code,
            minLines: 5,
            maxLines: 8,
            decoration: const InputDecoration(labelText: 'Code', alignLabelWithHint: true),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                final title = _title.text.trim().isEmpty ? 'Untitled snippet' : _title.text.trim();
                final language = _language.text.trim().isEmpty ? 'Text' : _language.text.trim();
                widget.onCreate(title, language);
                Navigator.pop(context);
              },
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save snippet'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeepDiveConsoleSheet extends StatefulWidget {
  const _DeepDiveConsoleSheet({
    required this.runtimeManager,
    required this.defaultProjectPath,
    required this.onLog,
    required this.onStartInChat,
  });

  final RuntimeManager runtimeManager;
  final String defaultProjectPath;
  final void Function(String title, String detail, IconData icon, Color color) onLog;
  final void Function(String prompt) onStartInChat;

  @override
  State<_DeepDiveConsoleSheet> createState() => _DeepDiveConsoleSheetState();
}

class _DeepDiveConsoleSheetState extends State<_DeepDiveConsoleSheet> {
  final _promptController = TextEditingController();
  final _projectPath = TextEditingController();
  final List<String> _lines = ['No deep dive action has run yet.'];
  bool _running = false;
  bool _cancelling = false;
  List<RuntimeTaskSnapshot> _recentTasks = const [];

  @override
  void initState() {
    super.initState();
    _promptController.text =
        'Inspect the selected project, run runtime preflight and validation, identify the next highest-value fix, implement it, and explain verification.';
    _projectPath.text = widget.defaultProjectPath;
  }

  @override
  void dispose() {
    _promptController.dispose();
    _projectPath.dispose();
    super.dispose();
  }

  void _startInChat() {
    final taskPrompt = _promptController.text.trim();
    if (taskPrompt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a task prompt first.')),
      );
      return;
    }
    final projectPath = _projectPath.text.trim();
    final prompt = [
      'Deep Dive task:',
      taskPrompt,
      if (projectPath.isNotEmpty) 'Project path / cwd: $projectPath',
      'Use RuntimeManager actions for preflight, validation, build, and recovery before making risky changes.',
    ].join('\n');
    Navigator.pop(context);
    widget.onStartInChat(prompt);
  }

  Future<void> _validateProject() async {
    final projectPath = _projectPath.text.trim();
    if (projectPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Project path is required.')),
      );
      return;
    }
    setState(() {
      _running = true;
      _lines.insert(0, 'Validating project...');
    });
    try {
      final result = await widget.runtimeManager.validateProject(
        projectPath: projectPath,
      );
      if (!mounted) return;
      final stepLines = result.steps.map((s) => '${s.success ? 'OK' : 'FAILED'} ${s.action.name}: ${s.summary}');
      setState(() {
        _lines.insert(
          0,
          [
            result.success ? 'VALIDATED: ${result.summary}' : 'VALIDATION STOPPED: ${result.summary}',
            ...stepLines,
            if (result.recoveryHint != null) 'Recovery: ${result.recoveryHint!}',
          ].join('\n'),
        );
      });
      widget.onLog(
        result.success ? 'Deep Dive validate completed' : 'Deep Dive validate stopped',
        result.summary,
        result.success ? Icons.verified_outlined : Icons.error_outline,
        result.success ? _mint : _rose,
      );
    } on Object catch (error) {
      if (!mounted) return;
      final message = _compact(error.toString(), limit: 180);
      setState(() => _lines.insert(0, 'VALIDATION ERROR: $message'));
      widget.onLog('Deep Dive validate error', message, Icons.error_outline, _rose);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _recoverHistory() async {
    setState(() {
      _running = true;
      _lines.insert(0, 'Loading task history...');
    });
    try {
      final tasks = await widget.runtimeManager.taskHistory(limit: 5);
      if (!mounted) return;
      setState(() {
        _recentTasks = tasks;
        _lines.insert(
          0,
          tasks.isEmpty
              ? 'No recoverable runtime task history.'
              : tasks.map(_taskSummary).join('\n\n'),
        );
      });
    } on Object catch (error) {
      if (!mounted) return;
      final message = _compact(error.toString(), limit: 180);
      setState(() => _lines.insert(0, 'Task history failed: $message'));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _cancelTask([String? taskId]) async {
    String? id = taskId;
    if (id == null) {
      for (final task in _recentTasks) {
        if (task.running) {
          id = task.taskId;
          break;
        }
      }
    }
    setState(() {
      _cancelling = true;
      _lines.insert(0, id == null ? 'Stopping active runtime task...' : 'Stopping runtime task $id...');
    });
    try {
      if (id == null) {
        await widget.runtimeManager.stopCurrentTask();
      } else {
        await widget.runtimeManager.stopTask(id);
      }
      final task = await widget.runtimeManager.currentTaskSnapshot();
      if (!mounted) return;
      setState(() {
        if (task != null) {
          _recentTasks = [task, ..._recentTasks.where((item) => item.taskId != task.taskId)].take(5).toList();
        }
        _lines.insert(0, task == null ? 'STOP REQUESTED: no recoverable runtime task.' : 'STOP REQUESTED: ${_taskSummary(task)}');
      });
      widget.onLog(
        'Deep Dive stop requested',
        task == null ? 'No recoverable runtime task after stop request.' : _taskSummary(task),
        Icons.stop_circle_outlined,
        _amber,
      );
    } on Object catch (error) {
      if (!mounted) return;
      final message = _compact(error.toString(), limit: 180);
      setState(() => _lines.insert(0, 'STOP ERROR: $message'));
      widget.onLog('Deep Dive stop failed', message, Icons.error_outline, _rose);
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  String _taskSummary(RuntimeTaskSnapshot task) {
    final logs = _recentLogLines(task.logs, limit: 4).join('\n');
    final failure = task.failureKind == RuntimeTaskFailureKind.none ? '' : ' (${task.failureKind.name})';
    return 'Task ${task.taskId} is ${task.status.name}$failure: ${task.command}${logs.isEmpty ? '' : '\n$logs'}';
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      icon: Icons.psychology_alt_outlined,
      title: 'Deep Dive',
      subtitle: 'Launch a multi-step coding session using the existing Chat Agent and RuntimeManager loop.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _promptController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Task prompt',
              hintText: 'Describe the coding task for the agent...',
              prefixIcon: Icon(Icons.edit_note_outlined),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _projectPath,
            decoration: const InputDecoration(labelText: 'Project path / cwd', prefixIcon: Icon(Icons.folder_outlined)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _RuntimeActionButton(
                icon: Icons.home_work_outlined,
                label: 'Default path',
                disabled: _running,
                onTap: () {
                  _projectPath.text = widget.defaultProjectPath;
                  setState(() => _lines.insert(0, 'Project path reset to default.'));
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          _Panel(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: _faint, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Uses the existing Chat Agent and RuntimeManager. No background task queue.',
                    style: const TextStyle(color: _faint, fontSize: 11, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _RuntimeActionButton(
                icon: Icons.chat_outlined,
                label: 'Start in Chat Agent',
                disabled: _running,
                onTap: _startInChat,
              ),
              _RuntimeActionButton(
                icon: Icons.verified_outlined,
                label: 'Validate project',
                disabled: _running,
                onTap: _validateProject,
              ),
              _RuntimeActionButton(
                icon: Icons.stop_circle_outlined,
                label: 'Stop runtime task',
                disabled: _cancelling,
                onTap: _cancelTask,
              ),
              _RuntimeActionButton(
                icon: Icons.history_outlined,
                label: 'Recover history',
                disabled: _running,
                onTap: _recoverHistory,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_recentTasks.isNotEmpty) ...[
            for (final task in _recentTasks.take(3)) ...[
              _TaskSnapshotPanel(
                task: task,
                onStop: task.canCancel ? () => _cancelTask(task.taskId) : null,
                onOpenDetails: () => _showRuntimeTaskDetailsSheet(
                  context: context,
                  runtimeManager: widget.runtimeManager,
                  task: task,
                  onLog: widget.onLog,
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
          _Panel(
            child: Text(
              _lines.take(8).join('\n\n'),
              style: const TextStyle(color: _muted, fontSize: 12, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _CapabilitySheet extends StatelessWidget {
  const _CapabilitySheet({
    required this.capability,
    required this.onRun,
    required this.onCopy,
  });

  final _Capability capability;
  final VoidCallback onRun;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      icon: capability.icon,
      title: capability.title,
      subtitle: capability.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(capability.subtitle, style: const TextStyle(color: _muted, height: 1.4)),
          const SizedBox(height: 16),
          const Text('Backend services', style: TextStyle(color: _text, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final service in capability.services) _MiniChip(label: service, color: _cyan),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Frontend actions', style: TextStyle(color: _text, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          for (final action in capability.actions)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.arrow_right_alt_outlined, color: _mint, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(action, style: const TextStyle(color: _muted))),
                ],
              ),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onRun,
                  icon: const Icon(Icons.play_arrow_outlined),
                  label: const Text('Open module'),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.outlined(
                tooltip: 'Copy service list',
                onPressed: onCopy,
                icon: const Icon(Icons.copy_outlined),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SheetScaffold extends StatelessWidget {
  const _SheetScaffold({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: _line,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(icon, color: _mint),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: _text, fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A2555FF),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.26)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _InlineStatus extends StatelessWidget {
  const _InlineStatus({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.09),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.24)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalToolRegistry extends StatelessWidget {
  const _LocalToolRegistry({
    required this.tools,
    this.title = 'Phone tool registry',
    this.subtitle,
    this.icon = Icons.handyman_outlined,
    this.color = _cyan,
  });

  final List<_LocalToolSpec> tools;
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 15),
                ),
              ),
              _Pill(label: '${tools.length} tools', icon: Icons.schema_outlined, color: color),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              style: const TextStyle(color: _muted, fontSize: 12, height: 1.35),
            ),
          ],
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 620 ? 3 : 2;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: tools.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  childAspectRatio: columns == 2 ? 1.12 : 1.34,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemBuilder: (context, index) => _LocalToolTile(tool: tools[index]),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _LocalToolTile extends StatelessWidget {
  const _LocalToolTile({required this.tool});

  final _LocalToolSpec tool;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _panelSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tool.color.withOpacity(0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(tool.icon, color: tool.color, size: 18),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  tool.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _text, fontSize: 12, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Text(
              tool.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _muted, fontSize: 11, height: 1.25),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              _MiniChip(label: tool.surface, color: tool.color),
              _MiniChip(label: tool.risk, color: _faint),
            ],
          ),
        ],
      ),
    );
  }
}

class _AndroidCommandMapPanel extends StatelessWidget {
  const _AndroidCommandMapPanel();

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.phone_android_outlined, color: _amber, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Android command map',
                  style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 15),
                ),
              ),
              _Pill(label: 'safe mapping', icon: Icons.shield_outlined, color: _amber),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'MobileCode does not expose a raw shell to the model. Common Android/Termux commands are mapped to typed tools when safe, or shown as blocked/runtime-only when they need more authority.',
            style: TextStyle(color: _muted, fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 10),
          for (final spec in _androidCommandSpecs) ...[
            _AndroidCommandRow(spec: spec),
            if (spec != _androidCommandSpecs.last) const Divider(height: 14, color: _line),
          ],
        ],
      ),
    );
  }
}

class _AndroidCommandRow extends StatelessWidget {
  const _AndroidCommandRow({required this.spec});

  final _AndroidCommandSpec spec;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: spec.color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: spec.color.withOpacity(0.35)),
          ),
          child: Icon(spec.icon, color: spec.color, size: 17),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      spec.category,
                      style: const TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 12),
                    ),
                  ),
                  _MiniChip(label: spec.support, color: spec.color),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                spec.commands,
                style: const TextStyle(color: _muted, fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 5),
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [
                  _MiniChip(label: spec.mobileCodePath, color: spec.color),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                spec.note,
                style: const TextStyle(color: _muted, fontSize: 11, height: 1.3),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AgentPresetToolMatrix extends StatelessWidget {
  const _AgentPresetToolMatrix();

  Color _presetColor(AgentPreset preset) {
    return switch (preset) {
      AgentPreset.autoAgent => _violet,
      AgentPreset.builder => _mint,
      AgentPreset.researchBuilder => _amber,
      AgentPreset.repair => _cyan,
      AgentPreset.reviewer => _blue,
    };
  }

  IconData _presetIcon(AgentPreset preset) {
    return switch (preset) {
      AgentPreset.autoAgent => Icons.auto_awesome_outlined,
      AgentPreset.builder => Icons.construction_outlined,
      AgentPreset.researchBuilder => Icons.travel_explore_outlined,
      AgentPreset.repair => Icons.healing_outlined,
      AgentPreset.reviewer => Icons.fact_check_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.account_tree_outlined, color: _mint, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Agent preset access',
                  style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 15),
                ),
              ),
              _Pill(label: 'no shell', icon: Icons.block_outlined, color: _rose),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'A model can only call the tools allowed by the selected Agent preset. Unsupported providers must fall back to Single-shot instead of pretending to be Agent Loop.',
            style: TextStyle(color: _muted, fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 10),
          for (final preset in AgentPreset.values) ...[
            _AgentPresetToolRow(
              preset: preset,
              color: _presetColor(preset),
              icon: _presetIcon(preset),
            ),
            if (preset != AgentPreset.values.last) const Divider(height: 14, color: _line),
          ],
        ],
      ),
    );
  }
}

class _AgentPresetToolRow extends StatelessWidget {
  const _AgentPresetToolRow({
    required this.preset,
    required this.color,
    required this.icon,
  });

  final AgentPreset preset;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.35)),
          ),
          child: Icon(icon, color: color, size: 17),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${preset.label} · ${preset.shortDescription}',
                style: const TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [
                  for (final toolName in preset.allowedToolNames) _MiniChip(label: toolName, color: color),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LocalToolTranscript extends StatelessWidget {
  const _LocalToolTranscript({
    required this.events,
    required this.running,
    required this.controller,
  });

  final List<_LocalToolEvent> events;
  final bool running;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final toolCalls = events.where((event) => event.kind == _LocalToolEventKind.toolCall).length;
    final observations = events.where((event) => event.kind == _LocalToolEventKind.observation).length;
    return _Panel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(running ? Icons.sync_outlined : Icons.timeline_outlined, color: running ? _amber : _violet, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Live code-writing transcript',
                  style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 15),
                ),
              ),
              _Pill(
                label: running ? 'Live' : '${events.length} events',
                icon: running ? Icons.bolt_outlined : Icons.receipt_long_outlined,
                color: running ? _amber : _violet,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MiniChip(label: '$toolCalls tool calls', color: _cyan),
              _MiniChip(label: '$observations results', color: _mint),
              _MiniChip(label: 'workspace-scoped', color: _amber),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: events.isEmpty ? 178 : 390,
            child: events.isEmpty
                ? const _LocalToolEmptyTranscript()
                : ListView.separated(
                    controller: controller,
                    itemCount: events.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => _LocalToolEventCard(event: events[index]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _LocalToolEmptyTranscript extends StatelessWidget {
  const _LocalToolEmptyTranscript();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _panelSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _line),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.play_circle_outline, color: _faint, size: 34),
          SizedBox(height: 10),
          Text(
            'Run the local tool test to watch tool calls, file writes, diff, and preview setup appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontSize: 12, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _LocalToolEventCard extends StatelessWidget {
  const _LocalToolEventCard({required this.event});

  final _LocalToolEvent event;

  @override
  Widget build(BuildContext context) {
    final color = _localToolEventColor(event);
    final isCodeLike = event.kind == _LocalToolEventKind.fileWrite ||
        event.kind == _LocalToolEventKind.diff ||
        event.kind == _LocalToolEventKind.toolCall;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_localToolEventIcon(event), color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  event.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _text, fontSize: 13, fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                event.durationMs == null ? _clockLabel(event.time) : '${event.durationMs}ms',
                style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          if (event.toolName != null || event.path != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (event.toolName != null) _MiniChip(label: event.toolName!, color: color),
                if (event.path != null) _MiniChip(label: _compact(event.path!, limit: 46), color: _faint),
              ],
            ),
          ],
          const SizedBox(height: 8),
          SelectableText(
            event.detail,
            style: TextStyle(
              color: event.ok ? _muted : _rose,
              fontSize: 12,
              height: 1.38,
              fontFamily: isCodeLike ? 'monospace' : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleProposalApprovalCard extends StatelessWidget {
  const _RoleProposalApprovalCard({
    required this.proposal,
    required this.onSave,
    required this.onDismiss,
    required this.onEdit,
  });

  final RoleProposal proposal;
  final VoidCallback onSave;
  final VoidCallback onDismiss;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final color = Color(proposal.role.colorValue);
    return _Panel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withOpacity(0.35)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: SvgPicture.asset(
                    proposal.role.avatarAsset,
                    fit: BoxFit.contain,
                    placeholderBuilder: (_) => Icon(Icons.person_add_alt_1_outlined, color: color, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Pending Approval',
                      style: TextStyle(color: _text, fontSize: 14, fontWeight: FontWeight.w900),
                    ),
                    Text(
                      '${proposal.role.name} · ${proposal.rationale}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _muted, fontSize: 11, height: 1.3),
                    ),
                  ],
                ),
              ),
              _Pill(label: 'local only', icon: Icons.lock_outline, color: _amber),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            proposal.role.mission,
            style: const TextStyle(color: _muted, fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MiniArtifactButton(icon: Icons.library_add_check_outlined, label: '保存到 Roles', onTap: onSave, color: _mint),
              _MiniArtifactButton(icon: Icons.edit_note_outlined, label: '编辑后保存', onTap: onEdit, color: _violet),
              _MiniArtifactButton(icon: Icons.close_outlined, label: '忽略', onTap: onDismiss, color: _faint),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoleProposalEditSheet extends StatefulWidget {
  const _RoleProposalEditSheet({required this.role});

  final MobileCodeRole role;

  @override
  State<_RoleProposalEditSheet> createState() => _RoleProposalEditSheetState();
}

class _RoleProposalEditSheetState extends State<_RoleProposalEditSheet> {
  late final TextEditingController _name;
  late final TextEditingController _mission;
  late final TextEditingController _personality;
  late final TextEditingController _responsibilities;
  late final TextEditingController _guardrails;
  late final TextEditingController _successCriteria;
  late final TextEditingController _promptTemplate;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.role.name);
    _mission = TextEditingController(text: widget.role.mission);
    _personality = TextEditingController(text: widget.role.personality);
    _responsibilities = TextEditingController(text: widget.role.responsibilities.join('\n'));
    _guardrails = TextEditingController(text: widget.role.guardrails.join('\n'));
    _successCriteria = TextEditingController(text: widget.role.successCriteria.join('\n'));
    _promptTemplate = TextEditingController(text: widget.role.promptTemplate);
  }

  @override
  void dispose() {
    _name.dispose();
    _mission.dispose();
    _personality.dispose();
    _responsibilities.dispose();
    _guardrails.dispose();
    _successCriteria.dispose();
    _promptTemplate.dispose();
    super.dispose();
  }

  List<String> _lines(TextEditingController controller) {
    return controller.text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .take(6)
        .toList(growable: false);
  }

  void _save() {
    final name = _name.text.trim();
    final mission = _mission.text.trim();
    if (name.isEmpty || mission.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name and mission are required.')));
      return;
    }
    final edited = widget.role.copyWith(
      name: name,
      summary: mission,
      mission: mission,
      personality: _personality.text.trim(),
      responsibilities: _lines(_responsibilities),
      guardrails: _lines(_guardrails),
      successCriteria: _lines(_successCriteria),
      promptTemplate: _promptTemplate.text.trim(),
      builtIn: false,
      enabled: true,
    );
    Navigator.of(context).pop(edited);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(
                children: [
                  Icon(Icons.edit_note_outlined, color: _violet, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('Edit role before saving', style: TextStyle(color: _text, fontSize: 16, fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'Role name')),
              const SizedBox(height: 8),
              TextField(controller: _mission, maxLines: 2, decoration: const InputDecoration(labelText: 'Mission')),
              const SizedBox(height: 8),
              TextField(controller: _personality, maxLines: 2, decoration: const InputDecoration(labelText: 'Personality')),
              const SizedBox(height: 8),
              TextField(controller: _responsibilities, maxLines: 3, decoration: const InputDecoration(labelText: 'Responsibilities, one per line')),
              const SizedBox(height: 8),
              TextField(controller: _guardrails, maxLines: 3, decoration: const InputDecoration(labelText: 'Guardrails, one per line')),
              const SizedBox(height: 8),
              TextField(controller: _successCriteria, maxLines: 3, decoration: const InputDecoration(labelText: 'Success criteria, one per line')),
              const SizedBox(height: 8),
              TextField(controller: _promptTemplate, minLines: 3, maxLines: 6, decoration: const InputDecoration(labelText: 'Prompt template')),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.library_add_check_outlined),
                      label: const Text('Save role'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgentRoleViewSheet extends StatelessWidget {
  const _AgentRoleViewSheet({
    required this.role,
    required this.index,
    this.step,
  });

  final MobileCodeRole role;
  final int index;
  final _AgentTraceStep? step;

  @override
  Widget build(BuildContext context) {
    final color = Color(role.colorValue);
    final state = step?.state ?? _AgentStepState.queued;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: color.withOpacity(0.35)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: SvgPicture.asset(
                      role.avatarAsset,
                      fit: BoxFit.contain,
                      placeholderBuilder: (_) => Icon(Icons.person_outline, color: color, size: 24),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(role.name, style: const TextStyle(color: _text, fontSize: 18, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      Text(role.summary.isEmpty ? role.mission : role.summary, style: const TextStyle(color: _muted, fontSize: 12, height: 1.35)),
                    ],
                  ),
                ),
                _Pill(label: 'Role ${index + 1}', icon: Icons.badge_outlined, color: color),
              ],
            ),
            const SizedBox(height: 14),
            _AgentViewStatusCard(step: step, state: state),
            const SizedBox(height: 12),
            _AgentViewTextBlock(title: 'Mission', text: role.mission),
            _AgentViewTextBlock(title: 'Personality', text: role.personality),
            _AgentViewListBlock(title: 'Responsibilities', values: role.responsibilities),
            _AgentViewListBlock(title: 'Guardrails', values: role.guardrails),
            _AgentViewListBlock(title: 'Success Criteria', values: role.successCriteria),
            if (role.promptTemplate.trim().isNotEmpty)
              _AgentViewTextBlock(title: 'Role Prompt', text: role.promptTemplate),
          ],
        ),
      ),
    );
  }
}

class _AgentViewStatusCard extends StatelessWidget {
  const _AgentViewStatusCard({required this.step, required this.state});

  final _AgentTraceStep? step;
  final _AgentStepState state;

  @override
  Widget build(BuildContext context) {
    final color = _agentStepColor(state);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_agentStepStatusIcon(state), color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  step?.title ?? 'Awaiting handoff',
                  style: const TextStyle(color: _text, fontSize: 14, fontWeight: FontWeight.w900),
                ),
              ),
              _Pill(label: _agentStepLabel(state), icon: _agentStepStatusIcon(state), color: color),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            step?.detail ?? 'This role has not taken a visible step in the current run yet.',
            style: const TextStyle(color: _muted, fontSize: 12, height: 1.35),
          ),
          if (step?.toolName != null) ...[
            const SizedBox(height: 8),
            _MiniChip(label: step!.toolName!, color: color),
          ],
        ],
      ),
    );
  }
}

class _AgentViewTextBlock extends StatelessWidget {
  const _AgentViewTextBlock({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: _text, fontSize: 13, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          SelectableText(text, style: const TextStyle(color: _muted, fontSize: 12, height: 1.4)),
        ],
      ),
    );
  }
}

class _AgentViewListBlock extends StatelessWidget {
  const _AgentViewListBlock({required this.title, required this.values});

  final String title;
  final List<String> values;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: _text, fontSize: 13, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          for (final value in values)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• ', style: TextStyle(color: _faint, fontSize: 12, height: 1.4)),
                  Expanded(child: Text(value, style: const TextStyle(color: _muted, fontSize: 12, height: 1.4))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AgentRecruitmentPanel extends StatelessWidget {
  const _AgentRecruitmentPanel({
    required this.steps,
    required this.running,
    required this.roles,
    required this.onOpenRole,
  });

  final List<_AgentTraceStep> steps;
  final bool running;
  final List<MobileCodeRole> roles;
  final void Function(MobileCodeRole role, int index) onOpenRole;

  _AgentStepState _roleState(int index) {
    if (steps.any((step) => step.state == _AgentStepState.failed)) {
      final failedIndex = steps.indexWhere((step) => step.state == _AgentStepState.failed);
      if (index > failedIndex) return _AgentStepState.queued;
      if (index == failedIndex) return _AgentStepState.failed;
    }
    final completed = steps.where((step) => step.state == _AgentStepState.done).length;
    if (index < completed) return _AgentStepState.done;
    if (running && index == completed) return _AgentStepState.running;
    return _AgentStepState.queued;
  }

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.groups_2_outlined, color: _violet, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Role Recruit · RR mode',
                  style: TextStyle(color: _text, fontSize: 14, fontWeight: FontWeight.w900),
                ),
              ),
              _Pill(
                label: running ? 'working' : 'ready',
                icon: running ? Icons.sync_outlined : Icons.verified_outlined,
                color: running ? _amber : _mint,
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'One execution lane, with different role personalities taking each stage.',
            style: TextStyle(color: _muted, fontSize: 11, height: 1.35),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 134,
            child: roles.isEmpty
                ? Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _panelSoft,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _line),
                    ),
                    child: const Text(
                      'No enabled roles. Open Control Center -> Roles to enable one.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: roles.length,
                    separatorBuilder: (context, index) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final role = roles[index];
                      return _AgentRoleCard(
                        role: role,
                        index: index,
                        state: _roleState(index),
                        onTap: () => onOpenRole(role, index),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _AgentRoleCard extends StatelessWidget {
  const _AgentRoleCard({
    required this.role,
    required this.index,
    required this.state,
    required this.onTap,
  });

  final MobileCodeRole role;
  final int index;
  final _AgentStepState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final stateColor = _agentStepColor(state);
    final roleColor = Color(role.colorValue);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 174,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: roleColor.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: stateColor.withOpacity(state == _AgentStepState.queued ? 0.22 : 0.48)),
        ),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: roleColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: roleColor.withOpacity(0.35)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: SvgPicture.asset(
                    role.avatarAsset,
                    fit: BoxFit.contain,
                    placeholderBuilder: (_) => Icon(Icons.person_outline, color: roleColor, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  role.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _text, fontSize: 12, fontWeight: FontWeight.w900),
                ),
              ),
              Text('${index + 1}'.padLeft(2, '0'), style: const TextStyle(color: _faint, fontSize: 10, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            role.mission,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _muted, fontSize: 10.5, height: 1.25),
          ),
          const Spacer(),
          Row(
            children: [
              Icon(_agentStepStatusIcon(state), color: stateColor, size: 14),
              const SizedBox(width: 5),
              Text(_agentStepLabel(state), style: TextStyle(color: stateColor, fontSize: 10.5, fontWeight: FontWeight.w900)),
            ],
          ),
        ],
      ),
      ),
    );
  }
}

class _AgentTracePanel extends StatelessWidget {
  const _AgentTracePanel({
    required this.title,
    required this.steps,
  });

  final String title;
  final List<_AgentTraceStep> steps;

  @override
  Widget build(BuildContext context) {
    final completed = steps.where((step) => step.state == _AgentStepState.done).length;
    final failed = steps.where((step) => step.state == _AgentStepState.failed).length;
    final running = steps.where((step) => step.state == _AgentStepState.running).length;
    final progress = steps.isEmpty ? 0.0 : (completed + failed) / steps.length;
    final liveStep = _latestAgentTraceStatusStep(steps);
    return _Panel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.timeline_outlined, color: _violet, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: _text, fontSize: 15, fontWeight: FontWeight.w900),
                ),
              ),
              _Pill(
                label: '$completed/${steps.length}',
                icon: Icons.task_alt_outlined,
                color: _violet,
              ),
            ],
          ),
          if (liveStep != null) ...[
            const SizedBox(height: 10),
            _AgentTraceLiveStatus(step: liveStep),
          ],
          const SizedBox(height: 12),
          for (var index = 0; index < steps.length; index++) ...[
            _AgentTraceRow(
              step: steps[index],
              index: index,
              isLast: index == steps.length - 1,
            ),
          ],
          const SizedBox(height: 12),
          _AgentTraceProgressFooter(
            progress: progress,
            completed: completed,
            running: running,
            failed: failed,
            total: steps.length,
          ),
        ],
      ),
    );
  }
}

_AgentTraceStep? _latestAgentTraceStatusStep(List<_AgentTraceStep> steps) {
  for (final step in steps.reversed) {
    if (step.state == _AgentStepState.running) return step;
  }
  for (final step in steps.reversed) {
    if (step.state != _AgentStepState.queued) return step;
  }
  return steps.isEmpty ? null : steps.first;
}

class _AgentTraceLiveStatus extends StatelessWidget {
  const _AgentTraceLiveStatus({required this.step});

  final _AgentTraceStep step;

  @override
  Widget build(BuildContext context) {
    final color = _agentStepColor(step.state);
    final label = step.state == _AgentStepState.running ? '当前状态' : '最新状态';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(step.state == _AgentStepState.running ? Icons.sync_outlined : _agentStepStatusIcon(step.state), color: color, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$label · ${step.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  step.detail,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 12, height: 1.34),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentTraceProgressFooter extends StatelessWidget {
  const _AgentTraceProgressFooter({
    required this.progress,
    required this.completed,
    required this.running,
    required this.failed,
    required this.total,
  });

  final double progress;
  final int completed;
  final int running;
  final int failed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final color = failed > 0 ? _rose : _mint;
    final percent = (progress * 100).round().clamp(0, 100);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _panelSoft.withOpacity(0.70),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.stacked_line_chart_outlined, color: color, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Progress · $percent%',
                  style: const TextStyle(color: _text, fontSize: 12, fontWeight: FontWeight.w900),
                ),
              ),
              Text('$completed/$total steps', style: const TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: _panel,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(label: '$completed done', icon: Icons.check_circle_outline, color: _mint),
              if (running > 0) _Pill(label: '$running running', icon: Icons.sync_outlined, color: _amber),
              if (failed > 0) _Pill(label: '$failed failed', icon: Icons.error_outline, color: _rose),
            ],
          ),
        ],
      ),
    );
  }
}

class _AgentTraceRow extends StatelessWidget {
  const _AgentTraceRow({
    required this.step,
    required this.index,
    required this.isLast,
  });

  final _AgentTraceStep step;
  final int index;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final color = _agentStepColor(step.state);
    final icon = _agentStepStatusIcon(step.state);
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _showAgentTraceStepDetails(context, step),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: step.state == _AgentStepState.running ? color.withOpacity(0.08) : _panelSoft.withOpacity(0.55),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(step.state == _AgentStepState.queued ? 0.18 : 0.35)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: color.withOpacity(0.42)),
                    ),
                    child: _AgentTraceAvatar(
                      assetPath: step.avatarAsset,
                      fallbackIcon: icon,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    (index + 1).toString().padLeft(2, '0'),
                    style: const TextStyle(color: _faint, fontSize: 10, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(step.icon, color: color, size: 15),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            step.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _Pill(label: _agentStepLabel(step.state), icon: icon, color: color),
                      ],
                    ),
                    if (step.toolName != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        step.toolName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      step.detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _muted, fontSize: 12, height: 1.35),
                    ),
                    if (step.details.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _AgentTraceInlineDetails(
                        details: step.details,
                        color: color,
                        initiallyExpanded: false,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, color: color.withOpacity(0.8), size: 18),
            ],
          ),
        ),
      ),
    );
  }

}

class _AgentTraceInlineDetails extends StatefulWidget {
  const _AgentTraceInlineDetails({
    required this.details,
    required this.color,
    this.initiallyExpanded = false,
  });

  final Map<String, String> details;
  final Color color;
  final bool initiallyExpanded;

  @override
  State<_AgentTraceInlineDetails> createState() => _AgentTraceInlineDetailsState();
}

class _AgentTraceInlineDetailsState extends State<_AgentTraceInlineDetails> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final visibleEntries = widget.details.entries
        .where((entry) => entry.value.trim().isNotEmpty)
        .toList(growable: false);
    if (visibleEntries.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: _panel.withOpacity(0.68),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: widget.color.withOpacity(0.22)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _expanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 10),
          childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          visualDensity: VisualDensity.compact,
          onExpansionChanged: (value) => setState(() => _expanded = value),
          leading: Icon(Icons.account_tree_outlined, color: widget.color, size: 16),
          title: Text(
            _expanded ? 'Hide provider/local tool details' : 'Show provider/local tool details',
            style: const TextStyle(color: _text, fontSize: 11.5, fontWeight: FontWeight.w900),
          ),
          children: [
            for (final entry in visibleEntries) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  entry.key,
                  style: TextStyle(color: widget.color, fontSize: 11, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(height: 3),
              Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(
                  entry.value,
                  style: const TextStyle(color: _muted, fontSize: 11, height: 1.34),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _AgentTraceAvatar extends StatelessWidget {
  const _AgentTraceAvatar({
    required this.assetPath,
    required this.fallbackIcon,
    required this.color,
  });

  final String? assetPath;
  final IconData fallbackIcon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final path = assetPath;
    if (path == null || path.isEmpty) {
      return Icon(fallbackIcon, color: color, size: 16);
    }

    return Padding(
      padding: const EdgeInsets.all(3),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SvgPicture.asset(
          path,
          fit: BoxFit.contain,
          placeholderBuilder: (_) => Icon(fallbackIcon, color: color, size: 16),
        ),
      ),
    );
  }
}

void _showAgentTraceStepDetails(BuildContext context, _AgentTraceStep step) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: _panel,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(10))),
    builder: (context) => _AgentTraceDetailSheet(step: step),
  );
}

class _AgentTraceDetailSheet extends StatelessWidget {
  const _AgentTraceDetailSheet({required this.step});

  final _AgentTraceStep step;

  @override
  Widget build(BuildContext context) {
    final color = _agentStepColor(step.state);
    final details = step.details.isEmpty
        ? {
            'Detail': step.detail,
          }
        : step.details;
    return _SheetScaffold(
      icon: step.icon,
      title: step.title,
      subtitle: step.toolName ?? _agentStepLabel(step.state),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(label: _agentStepLabel(step.state), icon: _agentStepStatusIcon(step.state), color: color),
              _Pill(label: 'evidence', icon: Icons.receipt_long_outlined, color: _violet),
              if (step.finishedAt != null) _Pill(label: _clockLabel(step.finishedAt!), icon: Icons.schedule_outlined, color: _cyan),
            ],
          ),
          const SizedBox(height: 12),
          _TraceDetailItem(label: 'Evidence ID', value: '${step.evidenceId} · ${step.traceAction.name}'),
          const SizedBox(height: 10),
          _Panel(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              step.detail,
              style: const TextStyle(color: _muted, fontSize: 12, height: 1.38),
            ),
          ),
          const SizedBox(height: 12),
          for (final entry in details.entries) ...[
            _TraceDetailItem(label: entry.key, value: entry.value),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _ActionEvidenceCenterSheet extends StatelessWidget {
  const _ActionEvidenceCenterSheet();

  @override
  Widget build(BuildContext context) {
    const maxItems = 12;
    final recent = ActionEvidenceStore.shared.recent(count: maxItems);
    final failures = ActionEvidenceStore.shared
        .failures()
        .where((evidence) => !evidence.success)
        .toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(
                children: [
                  Icon(Icons.receipt_long_outlined, color: _violet),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Activity / Logs',
                      style: TextStyle(color: _text, fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Local evidence from this app process only.',
                style: TextStyle(color: _muted, height: 1.35),
              ),
              const SizedBox(height: 14),
              if (recent.isEmpty && failures.isEmpty)
                const Text('No action evidence yet.', style: TextStyle(color: _muted))
              else ...[
                if (recent.isNotEmpty) ...[
                  const Text('Recent Action Evidence', style: TextStyle(color: _text, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  for (final evidence in recent.take(maxItems)) ...[
                    _ActionEvidenceCenterItem(
                      evidence: evidence,
                      onOpenDetails: evidence.success ? null : () => _showActionEvidenceSheet(context, evidence),
                    ),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 10),
                ],
                if (failures.isNotEmpty) ...[
                  const Text('Failed Action Evidence', style: TextStyle(color: _text, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  for (final evidence in failures.take(maxItems)) ...[
                    _ActionEvidenceCenterItem(
                      evidence: evidence,
                      onOpenDetails: () => _showActionEvidenceSheet(context, evidence),
                      showFailureCopy: true,
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionEvidenceCenterItem extends StatelessWidget {
  const _ActionEvidenceCenterItem({
    required this.evidence,
    this.onOpenDetails,
    this.showFailureCopy = false,
  });

  final ActionEvidence evidence;
  final VoidCallback? onOpenDetails;
  final bool showFailureCopy;

  @override
  Widget build(BuildContext context) {
    final status = evidence.success ? 'success' : (evidence.failureKind ?? 'failed');
    final card = _Panel(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                evidence.success ? Icons.check_circle_outline : Icons.error_outline,
                color: evidence.success ? _mint : _rose,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  evidence.actionName.name,
                  style: const TextStyle(color: _text, fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                status,
                style: TextStyle(color: evidence.success ? _mint : _rose, fontSize: 11, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _durationLabel(Duration(milliseconds: evidence.durationMs)),
            style: const TextStyle(color: _faint, fontSize: 11),
          ),
          if (evidence.artifactPaths.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Artifacts: ${evidence.artifactPaths.join(', ')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _muted, fontSize: 10),
            ),
          ],
          if (evidence.urls.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'URLs: ${evidence.urls.join(', ')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _muted, fontSize: 10),
            ),
          ],
          if (showFailureCopy && evidence.failureKind != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                IconButton(
                  tooltip: 'Copy failure summary',
                  visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _buildEvidenceFailureSummary(evidence)));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Failure summary copied')),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy_outlined, size: 18),
                ),
                const SizedBox(width: 2),
                const Text(
                  'Copy failure summary',
                  style: TextStyle(color: _muted, fontSize: 10),
                ),
              ],
            ),
          ],
        ],
      ),
    );

    if (onOpenDetails == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpenDetails,
        borderRadius: BorderRadius.circular(8),
        child: card,
      ),
    );
  }
}

void _showActionEvidenceSheet(BuildContext context, ActionEvidence evidence) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: _panel,
    builder: (context) {
      final evidenceDurationLabel = _durationLabel(Duration(milliseconds: evidence.durationMs));
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(evidence.success ? Icons.check_circle_outline : Icons.error_outline, color: evidence.success ? _mint : _rose),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        evidence.actionName.name,
                        style: const TextStyle(color: _text, fontSize: 18, fontWeight: FontWeight.w900),
                      ),
                    ),
                    _Pill(
                      label: evidence.success ? 'success' : (evidence.failureKind ?? 'failed'),
                      icon: evidence.success ? Icons.check_circle_outline : Icons.error_outline,
                      color: evidence.success ? _mint : _rose,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _EvidenceInfoRow(label: 'Evidence ID', value: evidence.evidenceId, monospace: true),
                _EvidenceInfoRow(label: 'Status', value: evidence.success ? 'success' : 'failed'),
                _EvidenceInfoRow(label: 'Duration', value: evidenceDurationLabel),
                _EvidenceInfoRow(label: 'Started', value: evidence.startedAt.toIso8601String()),
                _EvidenceInfoRow(label: 'Ended', value: evidence.endedAt.toIso8601String()),
                if (evidence.failureKind != null) _EvidenceInfoRow(label: 'Failure kind', value: evidence.failureKind!),
                if (evidence.paramsSummary.isNotEmpty) _EvidenceInfoRow(label: 'Params', value: evidence.paramsSummary),
                if (evidence.artifactPaths.isNotEmpty)
                  _EvidenceInfoRow(label: 'Artifacts', value: evidence.artifactPaths.join('\n'), monospace: true),
                if (evidence.urls.isNotEmpty)
                  _EvidenceInfoRow(label: 'URLs', value: evidence.urls.join('\n'), monospace: true),
                if (evidence.recoveryActions.isNotEmpty)
                  _EvidenceInfoRow(label: 'Recovery', value: evidence.recoveryActions.join('\n')),
                if (evidence.logs.isNotEmpty)
                  _EvidenceInfoRow(label: 'Logs', value: evidence.logs.join('\n'), monospace: true),
              ],
            ),
          ),
        ),
      );
    },
  );
}

String _buildEvidenceFailureSummary(ActionEvidence evidence) {
  final duration = _durationLabel(Duration(milliseconds: evidence.durationMs));
  final failure = evidence.failureKind ?? 'failed';
  final summary = <String>['Action: ${evidence.actionName.name}', 'Status: $failure', 'Duration: $duration'];
  if (evidence.artifactPaths.isNotEmpty) {
    summary.add('Artifacts: ${evidence.artifactPaths.join(' | ')}');
  }
  if (evidence.urls.isNotEmpty) {
    summary.add('URLs: ${evidence.urls.join(' | ')}');
  }
  if (evidence.recoveryActions.isNotEmpty) {
    summary.add('Recovery: ${evidence.recoveryActions.join(' | ')}');
  }
  if (evidence.logs.isNotEmpty) {
    summary.add('Logs: ${evidence.logs.take(6).join(' | ')}');
  }
  return summary.join('\n');
}

class _EvidenceInfoRow extends StatelessWidget {
  const _EvidenceInfoRow({
    required this.label,
    required this.value,
    this.monospace = false,
  });

  final String label;
  final String value;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: _faint, fontSize: 11, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          SelectableText(
            value,
            style: TextStyle(
              color: _muted,
              fontSize: 12,
              height: 1.35,
              fontFamily: monospace ? 'monospace' : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _TraceDetailItem extends StatelessWidget {
  const _TraceDetailItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: _text, fontSize: 12, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          SelectableText(
            value,
            style: const TextStyle(color: _muted, fontSize: 12, height: 1.38),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status, required this.color});

  final _CapabilityStatus status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _Pill(label: _statusLabel(status), icon: _statusIcon(status), color: color);
  }
}

String _agentStepLabel(_AgentStepState state) {
  return switch (state) {
    _AgentStepState.queued => 'Queued',
    _AgentStepState.running => 'Running',
    _AgentStepState.done => 'Done',
    _AgentStepState.failed => 'Failed',
  };
}

IconData _agentStepStatusIcon(_AgentStepState state) {
  return switch (state) {
    _AgentStepState.queued => Icons.radio_button_unchecked_outlined,
    _AgentStepState.running => Icons.sync_outlined,
    _AgentStepState.done => Icons.check_circle_outline,
    _AgentStepState.failed => Icons.error_outline,
  };
}

Color _agentStepColor(_AgentStepState state) {
  return switch (state) {
    _AgentStepState.queued => _faint,
    _AgentStepState.running => _amber,
    _AgentStepState.done => _mint,
    _AgentStepState.failed => _rose,
  };
}

Color _localToolEventColor(_LocalToolEvent event) {
  if (!event.ok || event.kind == _LocalToolEventKind.error) return _rose;
  return switch (event.kind) {
    _LocalToolEventKind.system => _cyan,
    _LocalToolEventKind.thought => _violet,
    _LocalToolEventKind.toolCall => _amber,
    _LocalToolEventKind.observation => _mint,
    _LocalToolEventKind.fileWrite => _blue,
    _LocalToolEventKind.diff => _lime,
    _LocalToolEventKind.preview => _violet,
    _LocalToolEventKind.finalAnswer => _mint,
    _LocalToolEventKind.error => _rose,
  };
}

IconData _localToolEventIcon(_LocalToolEvent event) {
  if (!event.ok || event.kind == _LocalToolEventKind.error) return Icons.error_outline;
  return switch (event.kind) {
    _LocalToolEventKind.system => Icons.memory_outlined,
    _LocalToolEventKind.thought => Icons.psychology_alt_outlined,
    _LocalToolEventKind.toolCall => Icons.play_circle_outline,
    _LocalToolEventKind.observation => Icons.check_circle_outline,
    _LocalToolEventKind.fileWrite => Icons.edit_note_outlined,
    _LocalToolEventKind.diff => Icons.compare_arrows_outlined,
    _LocalToolEventKind.preview => Icons.preview_outlined,
    _LocalToolEventKind.finalAnswer => Icons.task_alt_outlined,
    _LocalToolEventKind.error => Icons.error_outline,
  };
}

String _flavorLabel(_ApiFlavor flavor) {
  return switch (flavor) {
    _ApiFlavor.anthropic => 'Anthropic',
    _ApiFlavor.openAi => 'OpenAI',
  };
}

String _statusLabel(_CapabilityStatus status) {
  return switch (status) {
    _CapabilityStatus.ready => 'Ready',
    _CapabilityStatus.needsConfig => 'Config',
    _CapabilityStatus.local => 'Local',
    _CapabilityStatus.preview => 'Preview',
  };
}

IconData _statusIcon(_CapabilityStatus status) {
  return switch (status) {
    _CapabilityStatus.ready => Icons.check_circle_outline,
    _CapabilityStatus.needsConfig => Icons.tune_outlined,
    _CapabilityStatus.local => Icons.offline_bolt_outlined,
    _CapabilityStatus.preview => Icons.visibility_outlined,
  };
}

Color _statusColor(_CapabilityStatus status) {
  return switch (status) {
    _CapabilityStatus.ready => _mint,
    _CapabilityStatus.needsConfig => _amber,
    _CapabilityStatus.local => _lime,
    _CapabilityStatus.preview => _cyan,
  };
}

String _focusTitle(_HomeTab tab) {
  return switch (tab) {
    _HomeTab.control => 'Ready workspace',
    _HomeTab.ai => 'Agent conversation',
    _HomeTab.ship => 'Build and release',
    _HomeTab.guard => 'Runtime checks',
    _HomeTab.insight => 'Usage signal',
  };
}

String _focusSubtitle(_HomeTab tab) {
  return switch (tab) {
    _HomeTab.control => 'Provider, local tool test, GitHub, Runtime, and demo surfaces stay one tap away.',
    _HomeTab.ai => 'Persistent chat plus visible tool traces for phone-first coding.',
    _HomeTab.ship => 'GitHub Release, Android APK, iOS simulator build, Pages, and preview paths.',
    _HomeTab.guard => 'Provider health, tool probes, install checks, and local storage checks.',
    _HomeTab.insight => 'Recent activity, saved drafts, snippets, and build confidence signals.',
  };
}

IconData _focusIcon(_HomeTab tab) {
  return switch (tab) {
    _HomeTab.control => Icons.dashboard_customize_outlined,
    _HomeTab.ai => Icons.psychology_alt_outlined,
    _HomeTab.ship => Icons.rocket_launch_outlined,
    _HomeTab.guard => Icons.health_and_safety_outlined,
    _HomeTab.insight => Icons.insights_outlined,
  };
}

Color _focusColor(_HomeTab tab) {
  return switch (tab) {
    _HomeTab.control => _mint,
    _HomeTab.ai => _violet,
    _HomeTab.ship => _amber,
    _HomeTab.guard => _rose,
    _HomeTab.insight => _cyan,
  };
}

_ModuleAction _focusPrimaryAction(_HomeTab tab) {
  return switch (tab) {
    _HomeTab.control => _ModuleAction.webDemo,
    _HomeTab.ai => _ModuleAction.aiChat,
    _HomeTab.ship => _ModuleAction.build,
    _HomeTab.guard => _ModuleAction.healthCheck,
    _HomeTab.insight => _ModuleAction.toolLab,
  };
}

_ModuleAction _focusSecondaryAction(_HomeTab tab) {
  return switch (tab) {
    _HomeTab.control => _ModuleAction.githubTest,
    _HomeTab.ai => _ModuleAction.toolLab,
    _HomeTab.ship => _ModuleAction.githubTest,
    _HomeTab.guard => _ModuleAction.termuxCheck,
    _HomeTab.insight => _ModuleAction.project,
  };
}

String _focusPrimaryLabel(_HomeTab tab) {
  return switch (tab) {
    _HomeTab.control => 'Run local test',
    _HomeTab.ai => 'Open AI chat',
    _HomeTab.ship => 'Open release tools',
    _HomeTab.guard => 'Check provider health',
    _HomeTab.insight => 'Open tool lab',
  };
}

String _focusSecondaryLabel(_HomeTab tab) {
  return switch (tab) {
    _HomeTab.control => 'Open GitHub test',
    _HomeTab.ai => 'Open tool probes',
    _HomeTab.ship => 'Open GitHub test',
    _HomeTab.guard => 'Check runtime',
    _HomeTab.insight => 'Open project console',
  };
}

IconData _focusPrimaryIcon(_HomeTab tab) {
  return switch (tab) {
    _HomeTab.control => Icons.play_arrow_outlined,
    _HomeTab.ai => Icons.forum_outlined,
    _HomeTab.ship => Icons.rocket_launch_outlined,
    _HomeTab.guard => Icons.monitor_heart_outlined,
    _HomeTab.insight => Icons.handyman_outlined,
  };
}

IconData _focusSecondaryIcon(_HomeTab tab) {
  return switch (tab) {
    _HomeTab.control => Icons.hub_outlined,
    _HomeTab.ai => Icons.schema_outlined,
    _HomeTab.ship => Icons.hub_outlined,
    _HomeTab.guard => Icons.terminal_outlined,
    _HomeTab.insight => Icons.folder_open_outlined,
  };
}

String _focusHealthLabel(_HealthState health) {
  return switch (health) {
    _HealthState.healthy => 'healthy',
    _HealthState.failed => 'needs check',
    _HealthState.checking => 'checking',
    _HealthState.unknown => 'not checked',
  };
}

_CapabilityStatus _healthToStatus(_HealthState health) {
  return switch (health) {
    _HealthState.healthy => _CapabilityStatus.ready,
    _HealthState.failed => _CapabilityStatus.needsConfig,
    _HealthState.checking => _CapabilityStatus.preview,
    _HealthState.unknown => _CapabilityStatus.preview,
  };
}

Color _healthColor(_HealthState health) {
  return switch (health) {
    _HealthState.healthy => _mint,
    _HealthState.failed => _rose,
    _HealthState.checking => _amber,
    _HealthState.unknown => _cyan,
  };
}

String _timeLabel(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inSeconds < 60) return '${diff.inSeconds}s';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  return '${diff.inHours}h';
}

String _durationLabel(Duration duration) {
  if (duration.inMilliseconds < 1000) return '${duration.inMilliseconds}ms';
  if (duration.inMinutes < 1) return '${duration.inSeconds}s';
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '${duration.inMinutes}m ${seconds}s';
}

List<String> _recentLogLines(List<String> logs, {required int limit}) {
  if (limit <= 0) return const [];
  if (logs.length <= limit) return logs;
  return logs.skip(logs.length - limit).toList();
}

String? _gitUrlError(String url) {
  if (url.trim().isEmpty) return 'Git repository URL is required';
  if (RegExp(r'[\s`$;&|<>]').hasMatch(url)) return 'Git URL contains unsafe shell characters';
  final parsed = Uri.tryParse(url);
  if (parsed != null && (parsed.scheme == 'https' || parsed.scheme == 'http' || parsed.scheme == 'ssh') && parsed.host.isNotEmpty) {
    return null;
  }
  if (RegExp(r'^[A-Za-z0-9_.-]+@[A-Za-z0-9_.-]+:[A-Za-z0-9_./-]+(?:\.git)?$').hasMatch(url)) {
    return null;
  }
  return 'Use an https://, http://, ssh://, or git@host:owner/repo.git URL';
}

String _projectNameFromGitUrl(String url) {
  final parts = url.split(RegExp(r'[:/]')).where((part) => part.trim().isNotEmpty).toList();
  final raw = parts.isEmpty ? 'mobilecode_project' : parts.last;
  return raw.endsWith('.git') ? raw.substring(0, raw.length - 4) : raw;
}

String _safeProjectDirectoryName(String value) {
  final sanitized = value.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_').replaceAll(RegExp(r'^\.|\.$'), '');
  if (sanitized.isEmpty || sanitized == '.' || sanitized == '..') return 'mobilecode_project';
  return sanitized;
}

String _quoteCommandArg(String value) {
  return "'${value.replaceAll("'", "'\"'\"'")}'";
}

final List<_CapabilityLayer> _capabilityLayers = [
  _CapabilityLayer(
    name: 'AI Core',
    subtitle: 'Model gateway, multimodal input, local AI, API operations, and prompt templates.',
    icon: Icons.auto_awesome_outlined,
    color: _mint,
    capabilities: [
      _Capability(
        title: 'LLM Gateway',
        subtitle: 'Chat, complete, explain, fix, streaming responses, and context-aware prompts.',
        icon: Icons.forum_outlined,
        status: _CapabilityStatus.needsConfig,
        services: ['llm_service.dart', 'api_service.dart', 'coding_prompts.dart', 'context_injector.dart'],
        actions: ['Send real chat request', 'Switch OpenAI or Anthropic-compatible routes', 'Use coding prompt modes'],
        primaryAction: _ModuleAction.aiChat,
        surface: 'AI Chat sheet and provider health panel',
      ),
      _Capability(
        title: 'Multimodal Studio',
        subtitle: 'Screenshot, image, voice, and text input grouped for mobile coding tasks.',
        icon: Icons.image_search_outlined,
        status: _CapabilityStatus.preview,
        services: ['multimodal_llm_service.dart', 'screenshot_to_code_service.dart', 'voice_service.dart'],
        actions: ['Capture screenshot to code', 'Attach voice command', 'Inspect generated Flutter output'],
        primaryAction: _ModuleAction.inspect,
      ),
      _Capability(
        title: 'API Operations',
        subtitle: 'Multiple keys, provider priority, usage, quota alerts, and fallback planning.',
        icon: Icons.route_outlined,
        status: _CapabilityStatus.ready,
        services: ['api_manager_service.dart', 'api_usage_service.dart', 'secure_storage_service.dart'],
        actions: ['Save provider profile', 'Run health probe', 'Track token usage and budgets'],
        primaryAction: _ModuleAction.apiConfig,
      ),
      _Capability(
        title: 'Local AI',
        subtitle: 'On-device inference surface for offline or privacy-sensitive coding workflows.',
        icon: Icons.memory_outlined,
        status: _CapabilityStatus.local,
        services: ['local_ai_service.dart', 'offline_manager.dart', 'device_perf_service.dart'],
        actions: ['Inspect device readiness', 'Prefer local model when offline', 'Monitor memory and heat limits'],
        primaryAction: _ModuleAction.inspect,
      ),
    ],
  ),
  _CapabilityLayer(
    name: 'Agents',
    subtitle: 'Supervisor-worker orchestration, ReAct actions, Deep Dive Solo, and self-use automation.',
    icon: Icons.psychology_alt_outlined,
    color: _violet,
    capabilities: [
      _Capability(
        title: 'Supervisor Agents',
        subtitle: 'Dynamic expert routing for coding, planning, debugging, review, and release tasks.',
        icon: Icons.account_tree_outlined,
        status: _CapabilityStatus.preview,
        services: ['agent_orchestrator.dart', 'agent_action_system.dart', 'coding_prompts.dart'],
        actions: ['Plan task decomposition', 'Track action and observation loop', 'Route to expert worker'],
        primaryAction: _ModuleAction.deepDive,
      ),
      _Capability(
        title: 'Deep Dive Solo',
        subtitle: 'Background task queue with progress, isolate execution, and resumable task history.',
        icon: Icons.all_inclusive_outlined,
        status: _CapabilityStatus.ready,
        services: ['deep_dive_service.dart', 'deep_dive_task_manager.dart', 'foreground_service.dart'],
        actions: ['Queue long-running coding task', 'Watch progress', 'Resume task history'],
        primaryAction: _ModuleAction.deepDive,
      ),
      _Capability(
        title: 'Self-Use Actions',
        subtitle: 'App-level action registry for navigation, file, editor, terminal, and workflow automation.',
        icon: Icons.touch_app_outlined,
        status: _CapabilityStatus.preview,
        services: ['self_invocation_service.dart', 'self_action_registry.dart', 'navigation_controller.dart'],
        actions: ['Inspect 52 registered actions', 'Trigger UI-aware workflow', 'Audit action metadata'],
        primaryAction: _ModuleAction.inspect,
      ),
    ],
  ),
  _CapabilityLayer(
    name: 'Code',
    subtitle: 'Editor, LSP-like controls, code index, context injection, similarity, snippets, and terminal.',
    icon: Icons.code_outlined,
    color: _cyan,
    capabilities: [
      _Capability(
        title: 'Mobile Editor',
        subtitle: 'Tabs, syntax styling, search, replace, AI assists, and file draft entry points.',
        icon: Icons.edit_note_outlined,
        status: _CapabilityStatus.ready,
        services: ['editor_controller.dart', 'storage_service.dart', 'file_item.dart'],
        actions: ['Create file draft', 'Open code editing surface', 'Prepare AI context for current file'],
        primaryAction: _ModuleAction.newFile,
      ),
      _Capability(
        title: 'Code Intelligence',
        subtitle: 'SQLite FTS index, keyword extraction, context injection, and similarity analysis.',
        icon: Icons.manage_search_outlined,
        status: _CapabilityStatus.local,
        services: ['code_index_service.dart', 'context_injector.dart', 'code_similarity_service.dart'],
        actions: ['Index project files', 'Retrieve relevant context', 'Compare snippets by AST features'],
        primaryAction: _ModuleAction.project,
      ),
      _Capability(
        title: 'Snippets',
        subtitle: 'Capture reusable fragments and surface them beside projects, editor, and AI prompts.',
        icon: Icons.data_object_outlined,
        status: _CapabilityStatus.ready,
        services: ['snippet_provider.dart', 'storage_service.dart', 'sync_queue_service.dart'],
        actions: ['Save snippet', 'Prepare quick paste', 'Queue offline sync'],
        primaryAction: _ModuleAction.snippet,
      ),
      _Capability(
        title: 'Terminal',
        subtitle: 'Local shell state, command history, autocomplete, and streaming output surfaces.',
        icon: Icons.terminal_outlined,
        status: _CapabilityStatus.preview,
        services: ['terminal_service.dart', 'terminal_controller.dart', 'terminal_provider.dart'],
        actions: ['Prepare command session', 'Inspect output stream', 'Bridge to SSH or Runtime'],
        primaryAction: _ModuleAction.terminal,
      ),
    ],
  ),
  _CapabilityLayer(
    name: 'Remote',
    subtitle: 'SSH, Runtime, build orchestration, previews, GitHub, Gist, Pages, and WeChat publishing.',
    icon: Icons.cloud_sync_outlined,
    color: _amber,
    capabilities: [
      _Capability(
        title: 'Remote Dev',
        subtitle: 'SSH, SFTP, port forwarding, Runtime commands, and mobile Linux workflows.',
        icon: Icons.dns_outlined,
        status: _CapabilityStatus.needsConfig,
        services: ['ssh_service.dart', 'termux_service.dart', 'ssh_provider.dart'],
        actions: ['Attach host', 'Run remote command', 'Sync files through SFTP'],
        primaryAction: _ModuleAction.terminal,
      ),
      _Capability(
        title: 'Build Orchestrator',
        subtitle: 'APK, preview, static deploy, and mobile packaging command center.',
        icon: Icons.rocket_launch_outlined,
        status: _CapabilityStatus.ready,
        services: ['build_orchestrator.dart', 'preview_service.dart', 'termux_service.dart'],
        actions: ['Stage APK build', 'Inspect preview surface', 'Track release progress'],
        primaryAction: _ModuleAction.build,
      ),
      _Capability(
        title: 'GitHub Deep Work',
        subtitle: 'Repository browsing, issue/PR surfaces, Gists, Pages deploy, cache, and analytics.',
        icon: Icons.account_tree_outlined,
        status: _CapabilityStatus.preview,
        services: ['github_service.dart', 'github_deep_service.dart', 'github_gist_service.dart', 'github_pages_service.dart', 'github_cache_service.dart'],
        actions: ['Browse repo', 'Analyze PR or issue', 'Publish Gist or Pages site'],
        primaryAction: _ModuleAction.project,
      ),
      _Capability(
        title: 'WeChat Publish',
        subtitle: 'Mini-program upload and release pipeline surfaced beside GitHub and build flows.',
        icon: Icons.send_to_mobile_outlined,
        status: _CapabilityStatus.preview,
        services: ['wechat_publish_service.dart', 'build_orchestrator.dart', 'logger_service.dart'],
        actions: ['Prepare upload', 'Validate project metadata', 'Track publish log'],
        primaryAction: _ModuleAction.build,
      ),
    ],
  ),
  _CapabilityLayer(
    name: 'Guard',
    subtitle: 'Secure storage, biometrics, local database, offline sync, crash recovery, and HTTP policies.',
    icon: Icons.security_outlined,
    color: _rose,
    capabilities: [
      _Capability(
        title: 'Credential Vault',
        subtitle: 'AES storage, Android Keystore or iOS Keychain, biometrics, and key masking.',
        icon: Icons.lock_outline,
        status: _CapabilityStatus.ready,
        services: ['secure_storage_service.dart', 'biometric_service.dart', 'api_manager_service.dart'],
        actions: ['Protect API keys', 'Enable biometric unlock', 'Audit provider secrets'],
        primaryAction: _ModuleAction.apiConfig,
      ),
      _Capability(
        title: 'Offline First',
        subtitle: 'SQLite database, file storage, sync queue, conflict handling, and offline mode.',
        icon: Icons.offline_bolt_outlined,
        status: _CapabilityStatus.local,
        services: ['local_database_service.dart', 'storage_service.dart', 'sync_queue_service.dart', 'offline_manager.dart'],
        actions: ['Queue offline changes', 'Inspect conflict policy', 'Resume sync when network returns'],
        primaryAction: _ModuleAction.inspect,
      ),
      _Capability(
        title: 'Recovery and Scan',
        subtitle: 'Crash recovery, structured logs, binary analysis, and security scan surfaces.',
        icon: Icons.health_and_safety_outlined,
        status: _CapabilityStatus.preview,
        services: ['crash_recovery_service.dart', 'logger_service.dart', 'binary_analysis_service.dart'],
        actions: ['Inspect crash snapshot', 'Analyze APK or IPA', 'View structured logs'],
        primaryAction: _ModuleAction.inspect,
      ),
    ],
  ),
  _CapabilityLayer(
    name: 'Analytics',
    subtitle: 'Projects, memory, habits, feedback learning, API usage, and binary analysis.',
    icon: Icons.insights_outlined,
    color: _blue,
    capabilities: [
      _Capability(
        title: 'Project Brain',
        subtitle: 'Project creation, import, export, learning, knowledge generation, and stats.',
        icon: Icons.folder_special_outlined,
        status: _CapabilityStatus.ready,
        services: ['project_manager.dart', 'project_learning_service.dart', 'memory_service.dart'],
        actions: ['Create or import project', 'Learn project knowledge', 'Feed memory into prompts'],
        primaryAction: _ModuleAction.project,
      ),
      _Capability(
        title: 'Usage and Cost',
        subtitle: 'Token usage, quota, costs, projections, and provider alerts.',
        icon: Icons.query_stats_outlined,
        status: _CapabilityStatus.preview,
        services: ['api_usage_service.dart', 'api_manager_service.dart', 'feedback_learning_service.dart'],
        actions: ['Inspect usage projection', 'Set quota warning', 'Learn from answer feedback'],
        primaryAction: _ModuleAction.inspect,
      ),
      _Capability(
        title: 'Coding Habits',
        subtitle: 'Activity tracking, habits, achievements, and personal rhythm analytics.',
        icon: Icons.timeline_outlined,
        status: _CapabilityStatus.local,
        services: ['habit_service.dart', 'vibing_activity_service.dart', 'memory_service.dart'],
        actions: ['Track coding time', 'View habit summary', 'Generate improvement suggestions'],
        primaryAction: _ModuleAction.inspect,
      ),
    ],
  ),
  _CapabilityLayer(
    name: 'Tools',
    subtitle: 'Voice, screenshot-to-code, skill manager, remote skills, feature flags, logs, and notifications.',
    icon: Icons.construction_outlined,
    color: _lime,
    capabilities: [
      _Capability(
        title: 'Capture Tools',
        subtitle: 'Voice commands and screenshot-to-code flows for mobile-first AI coding.',
        icon: Icons.center_focus_strong_outlined,
        status: _CapabilityStatus.preview,
        services: ['voice_service.dart', 'screenshot_to_code_service.dart', 'multimodal_llm_service.dart'],
        actions: ['Capture voice task', 'Convert screenshot to Flutter', 'Send multimodal prompt'],
        primaryAction: _ModuleAction.inspect,
      ),
      _Capability(
        title: 'MCP and Skills',
        subtitle: 'Local and remote skill packages with import, metadata, and execution surfaces.',
        icon: Icons.extension_outlined,
        status: _CapabilityStatus.preview,
        services: ['skill_manager_service.dart', 'remote_skill_service.dart', 'self_action_registry.dart'],
        actions: ['Import skill from GitHub', 'Inspect tool metadata', 'Bind skill to agent action'],
        primaryAction: _ModuleAction.inspect,
      ),
      _Capability(
        title: 'Runtime Controls',
        subtitle: 'Feature flags, structured logger, notifications, and navigation state.',
        icon: Icons.tune_outlined,
        status: _CapabilityStatus.ready,
        services: ['feature_flags_service.dart', 'notification_manager.dart', 'navigation_controller.dart', 'logger_service.dart'],
        actions: ['Toggle rollout flag', 'Inspect notification queue', 'Audit navigation events'],
        primaryAction: _ModuleAction.inspect,
      ),
    ],
  ),
  _CapabilityLayer(
    name: 'Performance',
    subtitle: 'FPS, haptics, device performance, performance modes, memory, and activity stats.',
    icon: Icons.speed_outlined,
    color: _cyan,
    capabilities: [
      _Capability(
        title: 'Device Performance',
        subtitle: 'FPS tracking, CPU, memory, temperature, and adaptive performance modes.',
        icon: Icons.speed_outlined,
        status: _CapabilityStatus.local,
        services: ['fps_tracker.dart', 'device_perf_service.dart', 'performance_mode_service.dart'],
        actions: ['Watch frame budget', 'Switch performance mode', 'Inspect device pressure'],
        primaryAction: _ModuleAction.inspect,
      ),
      _Capability(
        title: 'Interaction Engine',
        subtitle: 'Haptics, animation timing, and activity feedback for mobile coding flows.',
        icon: Icons.vibration_outlined,
        status: _CapabilityStatus.ready,
        services: ['haptic_feedback_service.dart', 'vibing_activity_service.dart', 'performance_provider.dart'],
        actions: ['Trigger haptic profile', 'Track activity streak', 'Tune interaction density'],
        primaryAction: _ModuleAction.inspect,
      ),
    ],
  ),
  _CapabilityLayer(
    name: 'Team',
    subtitle: 'Team members, shared knowledge, collaboration surfaces, and foreground execution.',
    icon: Icons.groups_outlined,
    color: _amber,
    capabilities: [
      _Capability(
        title: 'Team Hub',
        subtitle: 'Members, permissions, shared projects, knowledge, and collaborative task views.',
        icon: Icons.groups_outlined,
        status: _CapabilityStatus.preview,
        services: ['team_service.dart', 'team_provider.dart', 'team_knowledge_screen.dart'],
        actions: ['Inspect members', 'Share project knowledge', 'Prepare collaboration backend endpoint'],
        primaryAction: _ModuleAction.inspect,
      ),
      _Capability(
        title: 'Foreground Runs',
        subtitle: 'Keep Deep Dive and long-running build tasks visible during background execution.',
        icon: Icons.notifications_active_outlined,
        status: _CapabilityStatus.preview,
        services: ['foreground_service.dart', 'notification_manager.dart', 'deep_dive_task_manager.dart'],
        actions: ['Publish progress notification', 'Keep background task alive', 'Resume from notification tap'],
        primaryAction: _ModuleAction.deepDive,
      ),
    ],
  ),
];
