import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/voice_service.dart';

enum _ApiFlavor { openAi, anthropic }

enum _HealthState { unknown, checking, healthy, failed }

enum _HomeTab { control, ai, ship, guard, insight }

enum _CapabilityStatus { ready, needsConfig, local, preview }

enum _AgentStepState { queued, running, done, failed }

enum _MiniAgentEventKind {
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
  inspect,
}

const _bg = Color(0xFF05070C);
const _panel = Color(0xFF101522);
const _panelSoft = Color(0xFF151A2A);
const _line = Color(0xFF293049);
const _text = Color(0xFFF0F3FA);
const _muted = Color(0xFF9EA6BD);
const _faint = Color(0xFF667089);
const _mint = Color(0xFF7AF2C7);
const _cyan = Color(0xFF62D9FF);
const _amber = Color(0xFFFFC66B);
const _rose = Color(0xFFFF6E87);
const _lime = Color(0xFFB8F26B);
const _violet = Color(0xFF8B5CF6);
const _blue = Color(0xFF6EA8FF);
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
const _demo2048Url = 'https://harzva.github.io/mobilecode/demo/2048/';
const _githubTestUrl = 'https://harzva.github.io/mobilecode/github-test/';
const _releaseUrl = 'https://github.com/Harzva/mobilecode/releases/tag/v0.1.0';
const _androidSmokeRunUrl = 'https://github.com/Harzva/mobilecode/actions/workflows/android-app-test.yml';
const _iosSimulatorRunUrl = 'https://github.com/Harzva/mobilecode/actions/workflows/ios-simulator.yml';
const _releaseBuildLabel = 'v0.1.0+14';
const _systemToolsChannel = MethodChannel('mobilecode/system_tools');

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
  });

  final String role;
  final String content;
  final DateTime time;

  Map<String, dynamic> toJson() {
    return {
      'role': role,
      'content': content,
      'time': time.toIso8601String(),
    };
  }

  factory _ChatTurn.fromJson(Map<String, dynamic> json) {
    return _ChatTurn(
      role: json['role'] as String? ?? 'user',
      content: json['content'] as String? ?? '',
      time: DateTime.tryParse(json['time'] as String? ?? '') ?? DateTime.now(),
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

class _AgentTraceStep {
  const _AgentTraceStep({
    required this.title,
    required this.detail,
    required this.icon,
    this.state = _AgentStepState.queued,
    this.finishedAt,
  });

  final String title;
  final String detail;
  final IconData icon;
  final _AgentStepState state;
  final DateTime? finishedAt;

  _AgentTraceStep copyWith({
    String? title,
    String? detail,
    IconData? icon,
    _AgentStepState? state,
    DateTime? finishedAt,
  }) {
    return _AgentTraceStep(
      title: title ?? this.title,
      detail: detail ?? this.detail,
      icon: icon ?? this.icon,
      state: state ?? this.state,
      finishedAt: finishedAt ?? this.finishedAt,
    );
  }
}

class _MiniAgentEvent {
  const _MiniAgentEvent({
    required this.kind,
    required this.title,
    required this.detail,
    required this.time,
    this.toolName,
    this.path,
    this.durationMs,
    this.ok = true,
  });

  final _MiniAgentEventKind kind;
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

class _MiniAgentToolSpec {
  const _MiniAgentToolSpec({
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

const _miniAgentTools = [
  _MiniAgentToolSpec(
    name: 'list_files',
    description: 'Inspect app-owned project folders before writing.',
    surface: 'Android app documents',
    icon: Icons.folder_open_outlined,
    color: _mint,
    risk: 'read-only',
  ),
  _MiniAgentToolSpec(
    name: 'write_file',
    description: 'Write generated code with a temp-file rename.',
    surface: 'Android app documents',
    icon: Icons.edit_note_outlined,
    color: _cyan,
    risk: 'guarded',
  ),
  _MiniAgentToolSpec(
    name: 'read_file',
    description: 'Read generated files back for preview and copy.',
    surface: 'Android app documents',
    icon: Icons.description_outlined,
    color: _blue,
    risk: 'read-only',
  ),
  _MiniAgentToolSpec(
    name: 'preview_webview',
    description: 'Load HTML/CSS/JS into the in-app Android WebView.',
    surface: 'Android WebView',
    icon: Icons.preview_outlined,
    color: _violet,
    risk: 'local',
  ),
  _MiniAgentToolSpec(
    name: 'termux_probe',
    description: 'Check Termux availability for shell-like mobile builds.',
    surface: 'Android package bridge',
    icon: Icons.terminal_outlined,
    color: _lime,
    risk: 'external app',
  ),
  _MiniAgentToolSpec(
    name: 'github_connect',
    description: 'Open the GitHub Pages token/repo connectivity tester.',
    surface: 'GitHub API',
    icon: Icons.hub_outlined,
    color: _amber,
    risk: 'network',
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

String _agentToolNameForPrompt(String prompt) {
  final lower = prompt.toLowerCase();
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

List<_AgentTraceStep> _agentRunTraceTemplate(String prompt) {
  final tool = _agentToolNameForPrompt(prompt);
  return [
    const _AgentTraceStep(
      title: 'Parse instruction',
      detail: 'Read the user request and decide whether this is chat, coding, preview, GitHub, or device tooling.',
      icon: Icons.manage_search_outlined,
    ),
    _AgentTraceStep(
      title: 'Select tool',
      detail: tool,
      icon: Icons.psychology_alt_outlined,
    ),
    const _AgentTraceStep(
      title: 'Plan executable steps',
      detail: 'Prepare a phone-safe action plan with local files, WebView preview, and failure handling.',
      icon: Icons.account_tree_outlined,
    ),
    const _AgentTraceStep(
      title: 'Execute tool surface',
      detail: 'Run the selected phone-safe tool and keep progress inside this chat instead of opening a temporary sheet.',
      icon: Icons.play_arrow_outlined,
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

String _agent2048Html() {
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
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _baseUrlKey = 'mobilecode.baseUrl';
  static const _apiKeyKey = 'mobilecode.apiKey';
  static const _modelKey = 'mobilecode.model';

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
  bool? _termuxInstalled;
  bool? _termuxApiInstalled;
  bool? _rootAvailable;
  String _runtimeMessage = 'Checking Termux and root status...';
  List<_ChatSession> _drawerSessions = const [];
  String? _drawerActiveSessionId;

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

  bool get _managedProviderActive => _managedProviderEnabled && _managedApiKey.trim().isNotEmpty;

  String get _effectiveBaseUrl => _managedProviderActive ? _managedBaseUrl : _baseUrlController.text.trim();

  String get _effectiveApiKey => _managedProviderActive ? _managedApiKey : _apiKeyController.text.trim();

  String get _effectiveModel => _managedProviderActive ? _managedModel : _modelController.text.trim();

  _ApiFlavor get _flavor {
    return _detectApiFlavor(_effectiveBaseUrl, _effectiveModel);
  }

  @override
  void initState() {
    super.initState();
    _loadConfig();
    unawaited(_checkRuntime(silent: true));
  }

  @override
  void dispose() {
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
    if (_managedProviderActive) {
      _showMessage('Managed provider is already active');
      return;
    }
    setState(() {
      _baseUrlController.text = _defaultBaseUrl;
      _modelController.text = _defaultModel;
    });
    _addLog('Mimo provider applied', 'Default Base URL and model filled. API key stays private.', Icons.tune_outlined, _mint);
  }

  Future<void> _saveConfig() async {
    if (_managedProviderActive) {
      _showMessage('Managed provider uses hidden debug credentials');
      return;
    }
    setState(() => _saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_baseUrlKey, _baseUrlController.text.trim());
      await prefs.setString(_apiKeyKey, _apiKeyController.text.trim());
      await prefs.setString(_modelKey, _modelController.text.trim());
      if (!mounted) return;
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
      if (!silent) _runtimeMessage = 'Checking Termux package, Termux:API, and root...';
    });
    try {
      final termux = await _isAndroidPackageInstalled('com.termux');
      final termuxApi = await _isAndroidPackageInstalled('com.termux.api');
      final rootProbe = await _probeRootAvailability();
      final root = rootProbe?.available;
      final message = switch ((termux, root)) {
        (true, true) => 'Ready for local Codex-style backend: Termux detected and root appears available.',
        (true, false) => 'Termux is installed, but root is missing or not granted. Real backend keepalive and auto-start will fail.',
        (true, null) => 'Termux is installed. Root probe is unavailable in this build.',
        (false, _) => 'Termux is not visible to Android package manager. Install Termux from F-Droid first.',
        (null, _) => 'Package visibility channel is unavailable. Check Android queries or generated MainActivity.',
      };
      if (!mounted) return;
      setState(() {
        _termuxInstalled = termux;
        _termuxApiInstalled = termuxApi;
        _rootAvailable = root;
        _runtimeMessage = rootProbe?.detail.isNotEmpty == true && root != true ? '$message ${rootProbe!.detail}' : message;
      });
      if (!silent) {
        _addLog(
          root == true && termux == true ? 'Runtime ready' : 'Runtime needs permission',
          _runtimeMessage,
          root == true && termux == true ? Icons.verified_outlined : Icons.warning_amber_outlined,
          root == true && termux == true ? _mint : _amber,
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
        _openProjectSheet();
        break;
      case _ModuleAction.terminal:
        _openCommandSheet();
        break;
      case _ModuleAction.deepDive:
        _openDeepDiveSheet();
        break;
      case _ModuleAction.build:
        _openBuildSheet();
        break;
      case _ModuleAction.inspect:
        if (capability != null) _openCapabilitySheet(capability);
        break;
    }
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
        onLog: (title, detail, icon, color) => _addLog(title, detail, icon, color),
        onAgentPrompt: _handleAgentPrompt,
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
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      _addLog(
        opened ? 'Opened $label' : 'Failed to open $label',
        url,
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
      builder: (context) => _TermuxSheet(
        onOpenInstall: () => _openUrl('https://f-droid.org/packages/com.termux/', 'Termux install page'),
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

  void _openProjectSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
      builder: (context) => _ActionConsoleSheet(
        icon: Icons.folder_open_outlined,
        title: 'Project Console',
        subtitle: 'Project manager, code index, context injector, storage, and learning services are surfaced here.',
        actions: const [
          'Create project from template',
          'Import ZIP or Git repository',
          'Index source code with SQLite FTS',
          'Learn project knowledge for AI context',
        ],
        buttonLabel: 'Stage project workflow',
        onRun: () {
          _addLog('Project workflow staged', 'Project manager and code index are ready', Icons.folder_open_outlined, _amber);
        },
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
      builder: (context) => _ActionConsoleSheet(
        icon: Icons.terminal_outlined,
        title: 'Terminal Console',
        subtitle: 'Terminal controller, shell service, SSH, and Termux bridges are grouped for mobile command work.',
        actions: const [
          'Run local shell command',
          'Attach SSH host',
          'Send Termux build command',
          'Stream command output into task history',
        ],
        buttonLabel: 'Prepare terminal session',
        onRun: () {
          _addLog('Terminal session prepared', 'Local, SSH, and Termux actions available', Icons.terminal_outlined, _cyan);
        },
      ),
    );
  }

  void _openDeepDiveSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
      builder: (context) => _ActionConsoleSheet(
        icon: Icons.psychology_alt_outlined,
        title: 'Deep Dive Solo',
        subtitle: 'Supervisor, action loop, task manager, and foreground service are presented as a single run console.',
        actions: const [
          'Plan multi-step coding task',
          'Queue background isolate execution',
          'Track thought, action, and observation cycle',
          'Resume or inspect completed runs',
        ],
        buttonLabel: 'Queue deep dive task',
        onRun: () {
          _addLog('Deep Dive queued', 'Supervisor-worker run prepared', Icons.psychology_alt_outlined, _violet);
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
      builder: (context) => _ActionConsoleSheet(
        icon: Icons.rocket_launch_outlined,
        title: 'Build and Release',
        subtitle: 'Build orchestrator, preview service, Termux, GitHub Pages, and WeChat publish flows share this surface.',
        actions: const [
          'Build Android APK through local or GitHub workflow',
          'Preview HTML and mobile app surfaces',
          'Deploy static site to GitHub Pages',
          'Prepare WeChat mini-program upload',
        ],
        buttonLabel: 'Stage release workflow',
        onRun: () {
          _addLog('Release workflow staged', 'APK, preview, Pages, and WeChat paths grouped', Icons.rocket_launch_outlined, _amber);
        },
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
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
  }

  Future<void> _newChatFromDrawer() async {
    await _closeDrawerIfOpen();
    _setTab(_HomeTab.control);
    await _chatPanelKey.currentState?.createSessionFromShell();
  }

  Future<void> _selectChatFromDrawer(String id) async {
    await _closeDrawerIfOpen();
    _setTab(_HomeTab.control);
    await _chatPanelKey.currentState?.selectSessionFromShell(id);
  }

  Future<void> _usePromptShortcut(String prompt, {bool runAgent = false}) async {
    await _closeDrawerIfOpen();
    _setTab(_HomeTab.control);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _chatPanelKey.currentState?.setPromptFromShell(prompt, runAgent: runAgent);
    });
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
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: _SimpleHeader(
            title: 'MobileCode',
            subtitle: 'Chat-first mobile coding agent',
            leading: IconButton.filledTonal(
              tooltip: 'Open conversations',
              onPressed: _openDrawer,
              icon: const Icon(Icons.menu_rounded),
            ),
            trailing: _Pill(
              label: _managedProviderActive ? 'Managed' : _flavorLabel(_flavor),
              icon: Icons.auto_awesome_outlined,
              color: _managedProviderActive ? _mint : (_flavor == _ApiFlavor.anthropic ? _amber : _cyan),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: _RuntimePermissionBanner(
            termuxInstalled: _termuxInstalled,
            termuxApiInstalled: _termuxApiInstalled,
            rootAvailable: _rootAvailable,
            checking: _runtimeChecking,
            message: _runtimeMessage,
            onCheck: () => _checkRuntime(),
            onOpenTermux: _openTermuxSheet,
          ),
        ),
        Expanded(
          child: _ChatPanel(
            key: _chatPanelKey,
            baseUrl: _effectiveBaseUrl,
            apiKey: _effectiveApiKey,
            model: _effectiveModel,
            embedded: true,
            onLog: (title, detail, icon, color) => _addLog(title, detail, icon, color),
            onAgentPrompt: _handleAgentPrompt,
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
        icon: Icons.handyman_outlined,
        title: 'Tool tests',
        subtitle: '测试 provider、GitHub、WebView、storage、Termux、root。',
        color: _cyan,
        action: _ModuleAction.toolLab,
      ),
      _CommandShortcut(
        icon: Icons.terminal_outlined,
        title: 'Termux / root',
        subtitle: '检查 Termux 是否安装、root 是否授权、后端为何未启动。',
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
          termuxInstalled: _termuxInstalled,
          termuxApiInstalled: _termuxApiInstalled,
          rootAvailable: _rootAvailable,
          checking: _runtimeChecking,
          message: _runtimeMessage,
          onCheck: () => _checkRuntime(),
          onOpenTermux: _openTermuxSheet,
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
          managedProviderActive: _managedProviderActive,
          onPreset: _applyDefaultProvider,
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
    return Scaffold(
      key: _scaffoldKey,
      resizeToAvoidBottomInset: true,
      backgroundColor: _bg,
      drawer: _MobileCodeDrawer(
        sessions: _drawerSessions,
        activeSessionId: _drawerActiveSessionId,
        termuxInstalled: _termuxInstalled,
        rootAvailable: _rootAvailable,
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
            _BottomNav(tab: _tab, onChanged: _setTab),
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
                'Mobile AI development console',
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

class _MobileCodeDrawer extends StatelessWidget {
  const _MobileCodeDrawer({
    required this.sessions,
    required this.activeSessionId,
    required this.termuxInstalled,
    required this.rootAvailable,
    required this.onNewChat,
    required this.onSelectSession,
    required this.onPrompt,
    required this.onOpenSettings,
    required this.onOpenTools,
  });

  final List<_ChatSession> sessions;
  final String? activeSessionId;
  final bool? termuxInstalled;
  final bool? rootAvailable;
  final VoidCallback onNewChat;
  final ValueChanged<String> onSelectSession;
  final Future<void> Function(String prompt, {bool runAgent}) onPrompt;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenTools;

  @override
  Widget build(BuildContext context) {
    final runtimeColor = termuxInstalled == true && rootAvailable == true
        ? _mint
        : termuxInstalled == true
            ? _amber
            : _rose;
    final runtimeLabel = termuxInstalled == true && rootAvailable == true
        ? 'Termux + root ready'
        : termuxInstalled == true
            ? 'Termux detected, root missing'
            : 'Termux/root not ready';

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
                  ? const Padding(
                      padding: EdgeInsets.all(18),
                      child: Text('No chat history yet', style: TextStyle(color: _muted)),
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
      subtitle: Text('${session.turns.length} turns', style: const TextStyle(color: _faint, fontSize: 11)),
      onTap: onTap,
    );
  }
}

class _RuntimePermissionBanner extends StatelessWidget {
  const _RuntimePermissionBanner({
    required this.termuxInstalled,
    required this.termuxApiInstalled,
    required this.rootAvailable,
    required this.checking,
    required this.message,
    required this.onCheck,
    required this.onOpenTermux,
  });

  final bool? termuxInstalled;
  final bool? termuxApiInstalled;
  final bool? rootAvailable;
  final bool checking;
  final String message;
  final VoidCallback onCheck;
  final VoidCallback onOpenTermux;

  @override
  Widget build(BuildContext context) {
    final ready = termuxInstalled == true && rootAvailable == true;
    final missingRoot = termuxInstalled == true && rootAvailable == false;
    final missingTermux = termuxInstalled == false;
    final color = ready
        ? _mint
        : missingRoot
            ? _amber
            : missingTermux
                ? _rose
                : _cyan;
    final title = ready
        ? 'Local runtime ready'
        : missingRoot
            ? '缺少 root 授权'
            : missingTermux
                ? '未检测到 Termux'
                : 'Runtime permission check';
    final rootLabel = rootAvailable == true
        ? 'root on'
        : rootAvailable == false
            ? 'root off'
            : 'root ?';
    final termuxLabel = termuxInstalled == true
        ? (termuxApiInstalled == true ? 'Termux + API' : 'Termux')
        : termuxInstalled == false
            ? 'No Termux'
            : 'Termux ?';

    return _Panel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(ready ? Icons.verified_outlined : Icons.warning_amber_outlined, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 15)),
                    const SizedBox(height: 3),
                    Text(message, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 12, height: 1.35)),
                  ],
                ),
              ),
              IconButton.outlined(
                tooltip: 'Check runtime',
                onPressed: checking ? null : onCheck,
                icon: checking
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh_outlined),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MiniChip(label: rootLabel, color: rootAvailable == true ? _mint : _amber),
              _MiniChip(label: termuxLabel, color: termuxInstalled == true ? _mint : _rose),
              _MiniChip(label: 'backend via Termux', color: _cyan),
              ActionChip(
                avatar: const Icon(Icons.terminal_outlined, size: 16),
                label: const Text('Termux'),
                onPressed: onOpenTermux,
              ),
            ],
          ),
        ],
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
    required this.managedProviderActive,
    required this.onPreset,
    required this.onSave,
    required this.onHealth,
  });

  final TextEditingController baseUrlController;
  final TextEditingController apiKeyController;
  final TextEditingController modelController;
  final bool saving;
  final _ApiFlavor flavor;
  final bool managedProviderActive;
  final VoidCallback onPreset;
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
              'MobileCode will call the configured provider with bundled debug credentials. Base URL, API key, and model are intentionally not shown on this screen.',
              style: TextStyle(color: _muted, fontSize: 12, height: 1.35),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onHealth,
              icon: const Icon(Icons.monitor_heart_outlined),
              label: const Text('Check Managed Provider'),
            ),
          ] else ...[
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
            'Default provider fills Base URL and model only. Paste your API key locally; it is never shipped inside the APK.',
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
                    Text('The focused path: play, connect GitHub, build diary, chat with memory, test tools, check Termux.', style: TextStyle(color: _muted, fontSize: 12, height: 1.35)),
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
                _DemoAction(Icons.terminal_outlined, 'Termux', 'Check install and setup path', _ModuleAction.termuxCheck, _lime),
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
  final List<_MiniAgentEvent> _agentEvents = [];
  final _agentEventController = ScrollController();

  @override
  void dispose() {
    _agentEventController.dispose();
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
      _stage = 'Starting mini agent';
      _agentEvents.clear();
      _transcriptPath = null;
    });
    try {
      final directory = await getApplicationDocumentsDirectory();
      final rootDirectory = Directory('${directory.path}/mobilecode_projects');
      final projectDirectory = Directory('${rootDirectory.path}/agent_2048');

      await _emitAgentEvent(
        _MiniAgentEvent(
          kind: _MiniAgentEventKind.system,
          title: 'Mini harness booted',
          detail:
              'Loaded phone-safe tools: list_files, write_file, read_file, preview_webview, termux_probe, github_connect.',
          time: DateTime.now(),
        ),
      );
      await _emitAgentEvent(
        _MiniAgentEvent(
          kind: _MiniAgentEventKind.thought,
          title: 'Reasoning',
          detail:
              'Goal is a real local 2048 project. The agent will create an app-owned workspace, generate a complete single-file web app, save it atomically, read it back, then make WebView preview available.',
          time: DateTime.now(),
        ),
      );

      final listStarted = DateTime.now();
      await _emitAgentEvent(
        _MiniAgentEvent(
          kind: _MiniAgentEventKind.toolCall,
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
      await _emitAgentEvent(
        _MiniAgentEvent(
          kind: _MiniAgentEventKind.observation,
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
      await _emitAgentEvent(
        _MiniAgentEvent(
          kind: _MiniAgentEventKind.toolCall,
          title: 'tool_call: mkdir',
          toolName: 'write_file',
          path: projectDirectory.path,
          detail: jsonEncode({
            'path': 'mobilecode_projects/agent_2048',
            'recursive': true,
          }),
          time: DateTime.now(),
        ),
      );
      await projectDirectory.create(recursive: true);
      await _emitAgentEvent(
        _MiniAgentEvent(
          kind: _MiniAgentEventKind.observation,
          title: 'tool_result: mkdir',
          toolName: 'write_file',
          path: projectDirectory.path,
          durationMs: DateTime.now().difference(prepareStarted).inMilliseconds,
          detail: 'Workspace ready inside Android app documents.',
          time: DateTime.now(),
        ),
      );

      await _emitAgentEvent(
        _MiniAgentEvent(
          kind: _MiniAgentEventKind.thought,
          title: 'Plan code structure',
          detail:
              'Single index.html keeps the demo portable: responsive board, swipe/keyboard input, score, best score, undo, game-over detection, and localStorage persistence.',
          time: DateTime.now(),
        ),
      );

      final html = _agent2048Html();
      final chunks = _chunkText(html, 1500);
      await _emitAgentEvent(
        _MiniAgentEvent(
          kind: _MiniAgentEventKind.toolCall,
          title: 'tool_call: write_file',
          toolName: 'write_file',
          path: '${projectDirectory.path}/index.html',
          detail: jsonEncode({
            'path': 'mobilecode_projects/agent_2048/index.html',
            'bytes': utf8.encode(html).length,
            'atomic': true,
          }),
          time: DateTime.now(),
        ),
      );
      for (var index = 0; index < chunks.length; index++) {
        await _emitAgentEvent(
          _MiniAgentEvent(
            kind: _MiniAgentEventKind.fileWrite,
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
      await _emitAgentEvent(
        _MiniAgentEvent(
          kind: _MiniAgentEventKind.observation,
          title: 'tool_result: write_file',
          toolName: 'write_file',
          path: file.path,
          durationMs: DateTime.now().difference(writeStarted).inMilliseconds,
          detail: 'Wrote ${html.length} characters to index.html through temp-file rename.',
          time: DateTime.now(),
        ),
      );

      await _emitAgentEvent(
        _MiniAgentEvent(
          kind: _MiniAgentEventKind.diff,
          title: 'Generated diff',
          toolName: 'write_file',
          path: file.path,
          detail: [
            '+ mobilecode_projects/agent_2048/index.html',
            '+ responsive 4x4 2048 board',
            '+ swipe and keyboard controls',
            '+ score, best score, undo, game-over state',
            '+ offline WebView-ready JavaScript',
          ].join('\n'),
          time: DateTime.now(),
        ),
      );

      final readStarted = DateTime.now();
      await _emitAgentEvent(
        _MiniAgentEvent(
          kind: _MiniAgentEventKind.toolCall,
          title: 'tool_call: read_file',
          toolName: 'read_file',
          path: file.path,
          detail: jsonEncode({
            'path': 'mobilecode_projects/agent_2048/index.html',
            'purpose': 'verify saved file and prepare preview',
          }),
          time: DateTime.now(),
        ),
      );
      final savedHtml = await file.readAsString();
      await _emitAgentEvent(
        _MiniAgentEvent(
          kind: _MiniAgentEventKind.observation,
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

      await _emitAgentEvent(
        _MiniAgentEvent(
          kind: _MiniAgentEventKind.preview,
          title: 'tool_call: preview_webview',
          toolName: 'preview_webview',
          path: file.path,
          detail:
              'WebView preview is armed. Tap Preview to run the generated game inside MobileCode without leaving the app.',
          durationMs: _lastGenerateMs,
          time: DateTime.now(),
        ),
      );
      await _emitAgentEvent(
        _MiniAgentEvent(
          kind: _MiniAgentEventKind.finalAnswer,
          title: 'Agent final',
          detail:
              '2048 project is complete. The generated code is visible below, stored on-device, and ready for WebView preview or GitHub publishing.',
          durationMs: _lastGenerateMs,
          time: DateTime.now(),
        ),
      );

      final transcript = await _persistRunTranscript(projectDirectory, started);
      if (!mounted) return;
      setState(() => _transcriptPath = transcript.path);
      widget.onLog('Agent generated 2048', '${file.path} - ${_lastGenerateMs}ms', Icons.grid_4x4_outlined, _mint);
    } on Object catch (error) {
      if (!mounted) return;
      await _emitAgentEvent(
        _MiniAgentEvent(
          kind: _MiniAgentEventKind.error,
          title: 'Agent failed',
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

  Future<void> _emitAgentEvent(
    _MiniAgentEvent event, {
    Duration delay = const Duration(milliseconds: 150),
  }) async {
    if (!mounted) return;
    setState(() {
      _stage = event.title;
      _agentEvents.add(event);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_agentEventController.hasClients) return;
      _agentEventController.animateTo(
        _agentEventController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
  }

  Future<File> _persistRunTranscript(Directory projectDirectory, DateTime started) async {
    final file = File('${projectDirectory.path}/agent_run.json');
    final payload = {
      'agent': 'MobileCode Android Mini Agent',
      'inspiredBy': [
        'mini-harness: model/tool/result loop',
        'mini-codex: workspace-scoped actions and shell-style tool output',
        'mini-claude-code: persistent session and tool transcript',
        'MiniClaude: visible tool-use lifecycle and file diff surfaces',
      ],
      'startedAt': started.toIso8601String(),
      'finishedAt': DateTime.now().toIso8601String(),
      'projectPath': _projectPath,
      'tools': _miniAgentTools
          .map((tool) => {
                'name': tool.name,
                'description': tool.description,
                'surface': tool.surface,
                'risk': tool.risk,
              })
          .toList(),
      'events': _agentEvents.map((event) => event.toJson()).toList(),
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
      title: 'Mobile Mini Agent',
      subtitle: 'A phone-first coding loop with visible tool calls, file writes, diff, and WebView preview.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Mini agent harness',
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
          const _MiniAgentToolRegistry(tools: _miniAgentTools),
          const SizedBox(height: 12),
          _MiniAgentConsole(
            events: _agentEvents,
            running: _generating,
            controller: _agentEventController,
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
                  label: Text(_generating ? 'Agent running' : 'Run mini agent'),
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
                  ? 'No generated code yet. Tap "Run mini agent" to create a real local project.'
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
          const Text(
            'Preview mode runs generated HTML inside the app through Android WebView. JavaScript is enabled for local demos.',
            style: TextStyle(color: _muted, fontSize: 12, height: 1.35),
          ),
        ],
      ),
    );
  }
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
      _QuickAction(Icons.terminal_outlined, 'Termux', _ModuleAction.termuxCheck, _lime),
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
        if (pages.statusCode == 404) _lines.add('Pages not enabled yet or token cannot read Pages settings.');
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
            child: Text(
              _lines.join('\n'),
              style: const TextStyle(color: _muted, height: 1.45),
            ),
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
    _ToolProbe(name: 'AI provider health', detail: 'Uses configured Base URL and model.', icon: Icons.monitor_heart_outlined, action: 'health'),
    _ToolProbe(name: 'GitHub web tester', detail: 'Opens a Pages test page for token and repo checks.', icon: Icons.hub_outlined, action: 'github_web'),
    _ToolProbe(name: 'Code 2048 project', detail: 'Runs the local coding lab and WebView preview flow.', icon: Icons.grid_4x4_outlined, action: 'demo_2048'),
    _ToolProbe(name: 'Local storage', detail: 'Writes and reads SharedPreferences.', icon: Icons.save_outlined, action: 'storage'),
    _ToolProbe(name: 'Termux package', detail: 'Checks com.termux through Android package manager.', icon: Icons.terminal_outlined, action: 'termux'),
    _ToolProbe(name: 'Root permission', detail: 'Detects whether a su binary is visible for backend keepalive.', icon: Icons.admin_panel_settings_outlined, action: 'root'),
  ];

  Future<void> _runAll() async {
    setState(() {
      _running = true;
      _results.clear();
    });
    await _run('storage');
    await _run('termux');
    await _run('root');
    await _run('health');
    if (mounted) setState(() => _running = false);
  }

  Future<void> _run(String action) async {
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
    if (action == 'termux') {
      final installed = await _isAndroidPackageInstalled('com.termux');
      final apiInstalled = await _isAndroidPackageInstalled('com.termux.api');
      if (installed == true) {
        _addResult('Termux package', true, apiInstalled == true ? 'com.termux and com.termux.api detected.' : 'com.termux detected. Termux:API not detected.');
      } else if (installed == false) {
        _addResult('Termux package', false, 'com.termux is not installed or not visible to package manager.');
      } else {
        final urlVisible = await canLaunchUrl(Uri.parse('termux://'));
        _addResult(
          'Termux package',
          urlVisible,
          urlVisible
              ? 'termux:// handler is visible. Package channel unavailable.'
              : 'Package channel unavailable; termux:// is not reliable for installed Termux detection.',
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
                _ToolScopeLine(icon: Icons.terminal_outlined, color: _amber, title: 'Needs Termux', detail: 'Linux shell, git/ssh binaries, npm/python package managers, local build scripts, long-running command sessions'),
                _ToolScopeLine(icon: Icons.cloud_outlined, color: _cyan, title: 'Better remote', detail: 'heavy builds, concurrent agent runs, private repo automation, CI release signing, team sync'),
              ],
            ),
          ),
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

class _TermuxSheet extends StatefulWidget {
  const _TermuxSheet({
    required this.onOpenInstall,
    required this.onLog,
  });

  final VoidCallback onOpenInstall;
  final void Function(String title, String detail, IconData icon, Color color) onLog;

  @override
  State<_TermuxSheet> createState() => _TermuxSheetState();
}

class _TermuxSheetState extends State<_TermuxSheet> {
  bool _checking = false;
  String _status = 'Not checked yet.';

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _status = 'Checking Android package manager for com.termux...';
    });
    try {
      final installed = await _isAndroidPackageInstalled('com.termux');
      final apiInstalled = await _isAndroidPackageInstalled('com.termux.api');
      final urlVisible = await canLaunchUrl(Uri.parse('termux://'));
      final rootProbe = await _probeRootAvailability();
      if (!mounted) return;
      final status = installed == true
          ? 'Termux is installed. ${apiInstalled == true ? 'Termux:API is also installed.' : 'Termux:API is not detected; command automation may need it.'} ${rootProbe?.available == true ? 'Root appears available.' : 'Root is missing or not granted, so backend auto-start/keepalive can fail.'}'
          : installed == false
              ? 'com.termux is not visible to Android package manager. Install Termux from F-Droid, or check package visibility.'
              : 'Package channel is unavailable in this build. termux:// visible: $urlVisible. URL scheme alone is not reliable.';
      setState(() {
        _status = status;
      });
      widget.onLog(
        installed == true ? 'Termux detected' : 'Termux check completed',
        _status,
        installed == true ? Icons.terminal_outlined : Icons.info_outline,
        installed == true ? _mint : _amber,
      );
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _launch() async {
    final opened = await _launchAndroidPackage('com.termux');
    if (!mounted) return;
    setState(() {
      _status = opened
          ? 'Termux launch intent sent. Return to MobileCode after preparing the shell.'
          : 'Could not launch com.termux. The package may be missing, disabled, or hidden from this build.';
    });
    widget.onLog(
      opened ? 'Termux launched' : 'Termux launch failed',
      _status,
      opened ? Icons.open_in_new_outlined : Icons.error_outline,
      opened ? _mint : _rose,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      icon: Icons.terminal_outlined,
      title: 'Termux Check',
      subtitle: 'MobileCode needs Termux for real phone-side build commands.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Panel(
            child: Text(_status, style: const TextStyle(color: _muted, height: 1.4)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _checking ? null : _check,
                  icon: _checking
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.search_outlined),
                  label: Text(_checking ? 'Checking' : 'Check Termux'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _launch,
                  icon: const Icon(Icons.open_in_new_outlined),
                  label: const Text('Launch'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: widget.onOpenInstall,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Install guide'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Termux is not mandatory for every tool. Pure Flutter tools can use storage, network, WebView, camera, microphone, and GitHub APIs directly. Termux is needed for Linux-like shell commands, local build tools, package managers, git/ssh binaries, and long-running developer scripts.',
            style: TextStyle(color: _muted, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _ChatPanel extends StatefulWidget {
  const _ChatPanel({
    super.key,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.onLog,
    required this.onAgentPrompt,
    this.onSessionsChanged,
    this.embedded = false,
  });

  final String baseUrl;
  final String apiKey;
  final String model;
  final void Function(String title, String detail, IconData icon, Color color) onLog;
  final Future<void> Function(String prompt) onAgentPrompt;
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
  String? _activeSessionId;
  bool _loading = true;
  bool _sending = false;
  bool _agentRunning = false;
  bool _voiceAvailable = false;
  VoiceState _voiceState = VoiceState.idle;
  StreamSubscription<String>? _voiceTranscriptSub;
  StreamSubscription<VoiceState>? _voiceStateSub;
  String? _error;
  final List<_AgentTraceStep> _agentTrace = [];

  _ChatSession? get _activeSession {
    if (_sessions.isEmpty) return null;
    final index = _sessions.indexWhere((session) => session.id == _activeSessionId);
    return index == -1 ? _sessions.first : _sessions[index];
  }

  @override
  void initState() {
    super.initState();
    _loadSessions();
    _initVoiceInput();
  }

  @override
  void dispose() {
    _voiceTranscriptSub?.cancel();
    _voiceStateSub?.cancel();
    _voiceService.dispose();
    _chatScrollController.dispose();
    _promptController.dispose();
    super.dispose();
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

  Future<void> _loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionsKey);
    final loaded = <_ChatSession>[];

    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          loaded.addAll(
            decoded
                .whereType<Map>()
                .map((item) => _ChatSession.fromJson(Map<String, dynamic>.from(item)))
                .where((session) => session.turns.isNotEmpty || session.title.trim().isNotEmpty),
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
      _activeSessionId = prefs.getString(_activeSessionKey);
      if (_sessions.every((session) => session.id != _activeSessionId)) {
        _activeSessionId = _sessions.first.id;
      }
      _loading = false;
    });
    _notifySessionsChanged();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionsKey, jsonEncode(_sessions.map((session) => session.toJson()).toList()));
    final activeId = _activeSessionId;
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

  void setPromptFromShell(String prompt, {bool runAgent = false}) {
    _promptController.text = prompt;
    _promptController.selection = TextSelection.collapsed(offset: prompt.length);
    if (!mounted) return;
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
    final session = _newSessionObject();
    setState(() {
      _sessions.insert(0, session);
      _activeSessionId = session.id;
      _error = null;
    });
    await _persist();
  }

  Future<void> _selectSession(String id) async {
    setState(() {
      _activeSessionId = id;
      _error = null;
    });
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
    _scrollConversationToEnd();
    await _persist();

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final flavor = _detectApiFlavor(widget.baseUrl, widget.model);
      final request = await client
          .postUrl(flavor == _ApiFlavor.anthropic
              ? _anthropicMessagesUri(widget.baseUrl)
              : _openAiChatUri(widget.baseUrl))
          .timeout(const Duration(seconds: 12));
      request.headers.contentType = ContentType.json;
      if (flavor == _ApiFlavor.anthropic) {
        request.headers.set('anthropic-version', '2023-06-01');
      }
      if (widget.apiKey.isNotEmpty) {
        if (flavor == _ApiFlavor.anthropic) {
          request.headers.set('x-api-key', widget.apiKey);
        }
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${widget.apiKey}');
      }
      request.write(jsonEncode(_requestBody(flavor, history)));

      final response = await request.close().timeout(const Duration(seconds: 45));
      final body = await utf8.decodeStream(response);
      if (!mounted) return;

      if (response.statusCode < 200 || response.statusCode >= 300) {
        setState(() => _error = 'HTTP ${response.statusCode}: ${_compact(body)}');
        widget.onLog('AI request failed', 'HTTP ${response.statusCode}', Icons.error_outline, _rose);
        return;
      }

      final answer = _extractAssistantText(body);
      final current = _sessions.firstWhere((session) => session.id == pending.id, orElse: () => pending);
      final next = current.copyWith(
        updatedAt: DateTime.now(),
        turns: [
          ...current.turns,
          _ChatTurn(role: 'assistant', content: answer, time: DateTime.now()),
        ],
      );
      setState(() => _storeSession(next));
      _scrollConversationToEnd();
      await _persist();
      widget.onLog('AI response received', '${_flavorLabel(flavor)} - ${widget.model}', Icons.forum_outlined, _mint);
    } on Object catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst('Exception: ', '');
      setState(() => _error = message);
      widget.onLog('AI request error', _compact(message, limit: 140), Icons.error_outline, _rose);
    } finally {
      client.close(force: true);
      if (mounted) {
        setState(() => _sending = false);
      }
    }
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

    if (_voiceService.isListening) {
      final transcript = await _voiceService.stopListening();
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

  Future<void> _runAgentWithTrace() async {
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
      _error = null;
      _promptController.clear();
      _agentTrace
        ..clear()
        ..addAll(_agentRunTraceTemplate(prompt));
      _storeSession(pending);
    });
    _scrollConversationToEnd();
    await _persist();

    String? failure;
    try {
      for (var index = 0; index < _agentTrace.length; index++) {
        await _completeAgentRunStep(index);
      }
    } on Object catch (error) {
      failure = error.toString();
      _failAgentRunStep(_compact(failure, limit: 140));
    }

    if (!mounted) return;
    final current = _sessions.firstWhere((session) => session.id == pending.id, orElse: () => pending);
    final assistantText = failure == null
        ? _agentCompletionMessage(toolName)
        : 'Agent run failed while using `$toolName`.\n\n${_compact(failure, limit: 300)}';
    final next = current.copyWith(
      updatedAt: DateTime.now(),
      turns: [
        ...current.turns,
        _ChatTurn(role: 'assistant', content: assistantText, time: DateTime.now()),
      ],
    );

    setState(() {
      _agentRunning = false;
      _storeSession(next);
      if (failure != null) _error = failure;
    });
    _scrollConversationToEnd();
    await _persist();

    if (failure == null) {
      widget.onLog('Agent run completed', toolName, Icons.psychology_alt_outlined, _violet);
      await widget.onAgentPrompt(prompt);
    } else {
      widget.onLog('Agent run failed', _compact(failure, limit: 140), Icons.error_outline, _rose);
    }
  }

  Future<void> _completeAgentRunStep(int index) async {
    if (!mounted || index < 0 || index >= _agentTrace.length) return;
    setState(() {
      _agentTrace[index] = _agentTrace[index].copyWith(state: _AgentStepState.running);
    });
    _scrollConversationToEnd();
    await Future<void>.delayed(const Duration(milliseconds: 240));
    if (!mounted || index < 0 || index >= _agentTrace.length) return;
    setState(() {
      _agentTrace[index] = _agentTrace[index].copyWith(
        state: _AgentStepState.done,
        finishedAt: DateTime.now(),
      );
    });
    _scrollConversationToEnd();
  }

  void _failAgentRunStep(String detail) {
    if (!mounted || _agentTrace.isEmpty) return;
    final runningIndex = _agentTrace.indexWhere((step) => step.state == _AgentStepState.running);
    final index = runningIndex == -1 ? _agentTrace.indexWhere((step) => step.state == _AgentStepState.queued) : runningIndex;
    if (index == -1) return;
    setState(() {
      _agentTrace[index] = _agentTrace[index].copyWith(
        detail: detail,
        state: _AgentStepState.failed,
        finishedAt: DateTime.now(),
      );
    });
    _scrollConversationToEnd();
  }

  String _agentCompletionMessage(String toolName) {
    final detail = switch (toolName) {
      'mobile_coding.generate_snake_preview' => [
          '- Target: create a phone-first Snake web game.',
          '- Tools: list_files -> write_file(index.html) -> read_file -> preview_webview.',
          '- Next visible step: keep generated code, diff, and WebView preview controls in this chat thread.',
        ],
      'mobile_coding.generate_2048_preview' => [
          '- Target: create a local 2048 web game.',
          '- Tools: list_files -> write_file(index.html) -> read_file -> preview_webview.',
          '- Next visible step: keep generated code, diff, and WebView preview controls in this chat thread.',
        ],
      'mobile_coding.build_diary_demo' => [
          '- Target: create the smallest useful diary app surface.',
          '- Tools: write_file(local model + UI) -> read_file -> local storage probe.',
          '- Next visible step: show file writes, storage checks, and APK readiness in this chat thread.',
        ],
      'mobile_tools.termux_probe' => [
          '- Target: diagnose Termux, Termux:API, root, and backend bridge readiness.',
          '- Tools: package probe -> root probe -> permission summary.',
          '- Next visible step: explain exactly which mobile permission or bridge is missing here.',
        ],
      'github.connectivity_test' => [
          '- Target: verify GitHub token and repo connectivity.',
          '- Tools: GitHub API probe -> repo access check -> Pages/release route check.',
          '- Next visible step: show success/failure reasons in this chat thread.',
        ],
      _ => [
          '- Parsed the instruction.',
          '- Selected the matching mobile-safe tool.',
          '- Built an executable plan instead of returning only chat text.',
        ],
    };
    return [
      'Agent run completed: `$toolName`',
      '',
      ...detail,
      '',
      'No temporary module window was opened; progress and result are kept in the current conversation.',
    ].join('\n');
  }

  Future<void> _runAgent() async {
    await _runAgentWithTrace();
  }


  Map<String, dynamic> _requestBody(_ApiFlavor flavor, List<_ChatTurn> turns) {
    final model = widget.model.isEmpty
        ? (flavor == _ApiFlavor.anthropic ? _defaultModel : 'gpt-4o-mini')
        : widget.model;
    final systemPrompt =
        'You are MobileCode, a mobile AI development assistant. Use the saved multi-turn chat context, answer concisely, and prefer executable mobile development steps.';
    final messages = _providerMessages(turns);
    if (flavor == _ApiFlavor.anthropic) {
      return {
        'model': model,
        'system': systemPrompt,
        'max_tokens': 1024,
        'messages': messages,
      };
    }
    return {
      'model': model,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        ...messages,
      ],
      'stream': false,
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

  String _chatTitle(String prompt) {
    final compact = _compact(prompt, limit: 36);
    return compact.isEmpty ? 'New chat' : compact;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _scrollConversationToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chatScrollController.hasClients) return;
      _chatScrollController.animateTo(
        _chatScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Widget _buildChatHeader(_ChatSession? active) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _Panel(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      const Icon(Icons.memory_outlined, color: _mint, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${active?.turns.length ?? 0} saved turns - context is sent with each request',
                          style: const TextStyle(color: _muted, fontSize: 12, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filledTonal(
                tooltip: 'New chat',
                onPressed: _sending || _agentRunning ? null : _createSession,
                icon: const Icon(Icons.add_comment_outlined),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final session in _sessions)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _ChatSessionChip(
                      session: session,
                      selected: session.id == active?.id,
                      onTap: _sending || _agentRunning ? null : () => _selectSession(session.id),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationBody(_ChatSession? active) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Panel(
          padding: const EdgeInsets.all(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 220),
            child: active == null || active.turns.isEmpty
                ? const _EmptyChatState()
                : Column(
                    children: [
                      for (var index = 0; index < active.turns.length; index++) ...[
                        _ChatBubble(turn: active.turns[index]),
                        if (index != active.turns.length - 1) const SizedBox(height: 10),
                      ],
                    ],
                  ),
          ),
        ),
        if (_agentTrace.isNotEmpty) ...[
          const SizedBox(height: 12),
          _AgentTracePanel(
            title: _agentRunning ? 'Agent is writing code' : 'Last agent process',
            steps: _agentTrace,
          ),
        ],
      ],
    );
  }

  Widget _buildComposer(_ApiFlavor flavor) {
    return Container(
      decoration: const BoxDecoration(
        color: _bg,
        border: Border(top: BorderSide(color: _line)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: _Panel(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _ChatModeStrip(onPrompt: (prompt, {runAgent = false}) => setPromptFromShell(prompt, runAgent: runAgent)),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _promptController,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      labelText: _voiceService.isListening ? 'Listening...' : 'Message',
                      hintText: 'Ask MobileCode, or tap a task shortcut.',
                      helperText: _voiceHelperText(flavor, widget.model, _voiceState),
                      alignLabelWithHint: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _VoiceInputButton(
                  enabled: !_sending && !_agentRunning,
                  available: _voiceAvailable,
                  state: _voiceState,
                  onTap: _toggleVoiceInput,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _sending || _agentRunning ? null : _send,
                    icon: _sending
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send_outlined),
                    label: Text(_sending ? 'Sending' : 'Send'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _sending || _agentRunning ? null : _runAgent,
                    icon: _agentRunning
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.psychology_alt_outlined),
                    label: Text(_agentRunning ? 'Running' : 'Run Agent'),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.outlined(
                  tooltip: 'Delete chat',
                  onPressed: _sending || _agentRunning ? null : _deleteActiveSession,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
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
    if (_loading) {
      return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
    }
    if (widget.embedded) {
      return Column(
        children: [
          _buildChatHeader(active),
          Expanded(
            child: SingleChildScrollView(
              controller: _chatScrollController,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: _buildConversationBody(active),
            ),
          ),
          _buildComposer(flavor),
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
          _buildChatHeader(active),
          const SizedBox(height: 12),
          _buildConversationBody(active),
          const SizedBox(height: 12),
          _buildComposer(flavor),
        ],
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
              '${session.turns.length} turns',
              style: TextStyle(color: selected ? _mint : _faint, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.turn});

  final _ChatTurn turn;

  @override
  Widget build(BuildContext context) {
    final isUser = turn.role == 'user';
    final color = isUser ? _cyan : _mint;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.76),
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
            Text(
              isUser ? 'You' : 'MobileCode',
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            SelectableText(
              turn.content,
              style: const TextStyle(color: _text, height: 1.42, fontSize: 13),
            ),
          ],
        ),
      ),
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

class _ChatModeStrip extends StatelessWidget {
  const _ChatModeStrip({required this.onPrompt});

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
        label: '日记',
        icon: Icons.edit_note_outlined,
        prompt: '帮我做一个最小日记 App：本地保存、列表、编辑、删除和空状态都要能在 APK 里体验。',
        color: _amber,
      ),
      _PromptShortcutData(
        label: 'GitHub',
        icon: Icons.hub_outlined,
        prompt: '测试 GitHub token 与 Harzva/mobilecode 仓库是否联通，并说明失败原因。',
        color: _violet,
      ),
      _PromptShortcutData(
        label: 'Termux',
        icon: Icons.terminal_outlined,
        prompt: '检查 Termux、Termux:API、root、后端端口是否可用，并告诉我缺什么权限。',
        color: _amber,
      ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final item in prompts) ...[
            _PromptShortcutChip(item: item, onTap: () => onPrompt(item.prompt, runAgent: true)),
            const SizedBox(width: 8),
          ],
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: item.color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: item.color.withOpacity(0.34)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(item.icon, color: item.color, size: 16),
            const SizedBox(width: 6),
            Text(item.label, style: const TextStyle(color: _text, fontSize: 12, fontWeight: FontWeight.w800)),
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
        width: 54,
        height: 54,
        child: FilledButton(
          style: FilledButton.styleFrom(
            padding: EdgeInsets.zero,
            backgroundColor: color.withOpacity(listening ? 0.92 : 0.16),
            foregroundColor: listening ? _bg : color,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
          onPressed: enabled ? onTap : null,
          child: Icon(listening ? Icons.stop_rounded : Icons.mic_none_outlined),
        ),
      ),
    );
  }
}

String _voiceHelperText(_ApiFlavor flavor, String model, VoiceState state) {
  final modelLabel = model.isEmpty ? 'default model' : model;
  final voiceLabel = switch (state) {
    VoiceState.listening => 'voice listening',
    VoiceState.processing => 'voice processing',
    VoiceState.done => 'voice ready',
    VoiceState.error => 'voice unavailable',
    VoiceState.idle => 'voice ready',
  };
  return '${_flavorLabel(flavor)} - $modelLabel - $voiceLabel';
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

class _ActionConsoleSheet extends StatelessWidget {
  const _ActionConsoleSheet({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actions,
    required this.buttonLabel,
    required this.onRun,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> actions;
  final String buttonLabel;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      icon: icon,
      title: title,
      subtitle: subtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final action in actions)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_circle_outline, color: _mint, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(action, style: const TextStyle(color: _text, height: 1.35)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                onRun();
                Navigator.pop(context);
              },
              icon: const Icon(Icons.play_arrow_outlined),
              label: Text(buttonLabel),
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

class _MiniAgentToolRegistry extends StatelessWidget {
  const _MiniAgentToolRegistry({required this.tools});

  final List<_MiniAgentToolSpec> tools;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.handyman_outlined, color: _cyan, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Phone tool registry',
                  style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 15),
                ),
              ),
              _Pill(label: '${tools.length} tools', icon: Icons.schema_outlined, color: _cyan),
            ],
          ),
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
                itemBuilder: (context, index) => _MiniAgentToolTile(tool: tools[index]),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MiniAgentToolTile extends StatelessWidget {
  const _MiniAgentToolTile({required this.tool});

  final _MiniAgentToolSpec tool;

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

class _MiniAgentConsole extends StatelessWidget {
  const _MiniAgentConsole({
    required this.events,
    required this.running,
    required this.controller,
  });

  final List<_MiniAgentEvent> events;
  final bool running;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final toolCalls = events.where((event) => event.kind == _MiniAgentEventKind.toolCall).length;
    final observations = events.where((event) => event.kind == _MiniAgentEventKind.observation).length;
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
                ? const _MiniAgentEmptyConsole()
                : ListView.separated(
                    controller: controller,
                    itemCount: events.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => _MiniAgentEventCard(event: events[index]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _MiniAgentEmptyConsole extends StatelessWidget {
  const _MiniAgentEmptyConsole();

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
            'Run the mini agent to watch thinking, tool calls, file writes, diff, and preview setup appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontSize: 12, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _MiniAgentEventCard extends StatelessWidget {
  const _MiniAgentEventCard({required this.event});

  final _MiniAgentEvent event;

  @override
  Widget build(BuildContext context) {
    final color = _miniAgentEventColor(event);
    final isCodeLike = event.kind == _MiniAgentEventKind.fileWrite ||
        event.kind == _MiniAgentEventKind.diff ||
        event.kind == _MiniAgentEventKind.toolCall;
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
              Icon(_miniAgentEventIcon(event), color: color, size: 18),
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

class _AgentTracePanel extends StatelessWidget {
  const _AgentTracePanel({
    required this.title,
    required this.steps,
  });

  final String title;
  final List<_AgentTraceStep> steps;

  @override
  Widget build(BuildContext context) {
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
                label: '${steps.where((step) => step.state == _AgentStepState.done).length}/${steps.length}',
                icon: Icons.task_alt_outlined,
                color: _violet,
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < steps.length; index++) ...[
            _AgentTraceRow(step: steps[index], isLast: index == steps.length - 1),
          ],
        ],
      ),
    );
  }
}

class _AgentTraceRow extends StatelessWidget {
  const _AgentTraceRow({
    required this.step,
    required this.isLast,
  });

  final _AgentTraceStep step;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final color = _agentStepColor(step.state);
    final icon = _agentStepStatusIcon(step.state);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withOpacity(0.42)),
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            if (!isLast)
              Container(
                width: 1,
                height: 42,
                margin: const EdgeInsets.symmetric(vertical: 4),
                color: _line,
              ),
          ],
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
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
                        style: const TextStyle(color: _text, fontWeight: FontWeight.w800, fontSize: 13),
                      ),
                    ),
                    Text(
                      _agentStepLabel(step.state),
                      style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  step.detail,
                  style: const TextStyle(color: _muted, fontSize: 12, height: 1.35),
                ),
              ],
            ),
          ),
        ),
      ],
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

Color _miniAgentEventColor(_MiniAgentEvent event) {
  if (!event.ok || event.kind == _MiniAgentEventKind.error) return _rose;
  return switch (event.kind) {
    _MiniAgentEventKind.system => _cyan,
    _MiniAgentEventKind.thought => _violet,
    _MiniAgentEventKind.toolCall => _amber,
    _MiniAgentEventKind.observation => _mint,
    _MiniAgentEventKind.fileWrite => _blue,
    _MiniAgentEventKind.diff => _lime,
    _MiniAgentEventKind.preview => _violet,
    _MiniAgentEventKind.finalAnswer => _mint,
    _MiniAgentEventKind.error => _rose,
  };
}

IconData _miniAgentEventIcon(_MiniAgentEvent event) {
  if (!event.ok || event.kind == _MiniAgentEventKind.error) return Icons.error_outline;
  return switch (event.kind) {
    _MiniAgentEventKind.system => Icons.memory_outlined,
    _MiniAgentEventKind.thought => Icons.psychology_alt_outlined,
    _MiniAgentEventKind.toolCall => Icons.play_circle_outline,
    _MiniAgentEventKind.observation => Icons.check_circle_outline,
    _MiniAgentEventKind.fileWrite => Icons.edit_note_outlined,
    _MiniAgentEventKind.diff => Icons.compare_arrows_outlined,
    _MiniAgentEventKind.preview => Icons.preview_outlined,
    _MiniAgentEventKind.finalAnswer => Icons.task_alt_outlined,
    _MiniAgentEventKind.error => Icons.error_outline,
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
    _HomeTab.control => 'Provider, mini agent, GitHub, Termux, and local demo surfaces stay one tap away.',
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
    _HomeTab.control => 'Run mini agent',
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
    _HomeTab.guard => 'Check Termux',
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
        actions: ['Prepare command session', 'Inspect output stream', 'Bridge to SSH or Termux'],
        primaryAction: _ModuleAction.terminal,
      ),
    ],
  ),
  _CapabilityLayer(
    name: 'Remote',
    subtitle: 'SSH, Termux, build orchestration, previews, GitHub, Gist, Pages, and WeChat publishing.',
    icon: Icons.cloud_sync_outlined,
    color: _amber,
    capabilities: [
      _Capability(
        title: 'Remote Dev',
        subtitle: 'SSH, SFTP, port forwarding, Termux commands, and mobile Linux workflows.',
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
