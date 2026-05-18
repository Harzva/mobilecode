import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const rolePolishSystemPrompt = '''
You are MobileCode Role Standardizer.

Turn a user's rough role idea into a production-ready MobileCode role card.
Return JSON only. Do not include markdown fences.

Schema:
{
  "name": "2-4 words",
  "summary": "one short sentence",
  "mission": "what this role owns in one execution lane",
  "personality": "working style and tone",
  "responsibilities": ["3-5 concrete responsibilities"],
  "guardrails": ["2-4 boundaries this role must respect"],
  "successCriteria": ["2-4 observable acceptance criteria"],
  "promptTemplate": "system-style role prompt written in second person"
}

Rules:
- MobileCode runs these roles as role personalities inside one agent execution lane, not as parallel agents.
- Keep the role useful for mobile coding, HTML generation, GitHub Pages, runtime diagnostics, or release QA.
- Avoid vague titles like Expert or Assistant unless the user explicitly asked for that name.
- The role must be bounded, testable, and safe for a mobile app environment.
''';

class MobileCodeRole {
  const MobileCodeRole({
    required this.id,
    required this.name,
    required this.summary,
    required this.mission,
    required this.personality,
    required this.responsibilities,
    required this.guardrails,
    required this.successCriteria,
    required this.promptTemplate,
    required this.avatarAsset,
    required this.colorValue,
    this.builtIn = false,
    this.enabled = true,
  });

  final String id;
  final String name;
  final String summary;
  final String mission;
  final String personality;
  final List<String> responsibilities;
  final List<String> guardrails;
  final List<String> successCriteria;
  final String promptTemplate;
  final String avatarAsset;
  final int colorValue;
  final bool builtIn;
  final bool enabled;

  MobileCodeRole copyWith({
    String? id,
    String? name,
    String? summary,
    String? mission,
    String? personality,
    List<String>? responsibilities,
    List<String>? guardrails,
    List<String>? successCriteria,
    String? promptTemplate,
    String? avatarAsset,
    int? colorValue,
    bool? builtIn,
    bool? enabled,
  }) {
    return MobileCodeRole(
      id: id ?? this.id,
      name: name ?? this.name,
      summary: summary ?? this.summary,
      mission: mission ?? this.mission,
      personality: personality ?? this.personality,
      responsibilities: responsibilities ?? this.responsibilities,
      guardrails: guardrails ?? this.guardrails,
      successCriteria: successCriteria ?? this.successCriteria,
      promptTemplate: promptTemplate ?? this.promptTemplate,
      avatarAsset: avatarAsset ?? this.avatarAsset,
      colorValue: colorValue ?? this.colorValue,
      builtIn: builtIn ?? this.builtIn,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'summary': summary,
      'mission': mission,
      'personality': personality,
      'responsibilities': responsibilities,
      'guardrails': guardrails,
      'successCriteria': successCriteria,
      'promptTemplate': promptTemplate,
      'avatarAsset': avatarAsset,
      'colorValue': colorValue,
      'builtIn': builtIn,
      'enabled': enabled,
    };
  }

  factory MobileCodeRole.fromJson(Map<String, dynamic> json) {
    return MobileCodeRole(
      id: json['id'] as String? ?? _newCustomRoleId(),
      name: json['name'] as String? ?? 'Custom Role',
      summary: json['summary'] as String? ?? '',
      mission: json['mission'] as String? ?? '',
      personality: json['personality'] as String? ?? '',
      responsibilities: _stringList(json['responsibilities']),
      guardrails: _stringList(json['guardrails']),
      successCriteria: _stringList(json['successCriteria']),
      promptTemplate: json['promptTemplate'] as String? ?? '',
      avatarAsset: json['avatarAsset'] as String? ?? RoleLibraryService.defaultCustomAvatarAsset,
      colorValue: json['colorValue'] as int? ?? 0xFF7557E8,
      builtIn: json['builtIn'] as bool? ?? false,
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}

enum RoleProposalStatus { pending, accepted, dismissed }

class RoleProposal {
  const RoleProposal({
    required this.proposalId,
    required this.sourceRoleId,
    required this.role,
    required this.prompt,
    required this.rationale,
    required this.runId,
    required this.status,
    required this.createdAt,
  });

  final String proposalId;
  final String sourceRoleId;
  final MobileCodeRole role;
  final String prompt;
  final String rationale;
  final String runId;
  final RoleProposalStatus status;
  final DateTime createdAt;

  RoleProposal copyWith({
    String? proposalId,
    String? sourceRoleId,
    MobileCodeRole? role,
    String? prompt,
    String? rationale,
    String? runId,
    RoleProposalStatus? status,
    DateTime? createdAt,
  }) {
    return RoleProposal(
      proposalId: proposalId ?? this.proposalId,
      sourceRoleId: sourceRoleId ?? this.sourceRoleId,
      role: role ?? this.role,
      prompt: prompt ?? this.prompt,
      rationale: rationale ?? this.rationale,
      runId: runId ?? this.runId,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'proposalId': proposalId,
      'sourceRoleId': sourceRoleId,
      'role': role.toJson(),
      'prompt': prompt,
      'rationale': rationale,
      'runId': runId,
      'status': status.name,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory RoleProposal.fromJson(Map<String, dynamic> json) {
    final statusName = json['status'] as String? ?? RoleProposalStatus.pending.name;
    return RoleProposal(
      proposalId: json['proposalId'] as String? ?? _newRoleProposalId(),
      sourceRoleId: json['sourceRoleId'] as String? ?? '',
      role: MobileCodeRole.fromJson(Map<String, dynamic>.from(json['role'] as Map? ?? const {}))
          .copyWith(builtIn: false),
      prompt: json['prompt'] as String? ?? '',
      rationale: json['rationale'] as String? ?? '',
      runId: json['runId'] as String? ?? '',
      status: RoleProposalStatus.values.firstWhere(
        (item) => item.name == statusName,
        orElse: () => RoleProposalStatus.pending,
      ),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

class RoleLibraryService extends ChangeNotifier {
  RoleLibraryService._();

  static final RoleLibraryService instance = RoleLibraryService._();

  static const defaultCustomAvatarAsset = 'assets/role_avatars/avatar-batch2-24-rounded-icon.svg';

  static const _customRolesKey = 'mobilecode.role_library.custom.v1';
  static const _disabledRoleIdsKey = 'mobilecode.role_library.disabled.v1';
  static const _roleProposalsKey = 'mobilecode.role_library.proposals.v1';

  SharedPreferences? _prefs;
  bool _initialized = false;
  final List<MobileCodeRole> _roles = [];
  final List<RoleProposal> _proposals = [];

  bool get isInitialized => _initialized;

  List<MobileCodeRole> get allRoles => List.unmodifiable(_roles);

  List<MobileCodeRole> get enabledRoles =>
      _roles.where((role) => role.enabled).toList(growable: false);

  List<RoleProposal> get pendingProposals => _proposals
      .where((proposal) => proposal.status == RoleProposalStatus.pending)
      .toList(growable: false);

  List<MobileCodeRole> get recruitmentRoles {
    if (_roles.isEmpty) return _defaultRoles.take(5).toList(growable: false);
    return enabledRoles.take(5).toList(growable: false);
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    _roles
      ..clear()
      ..addAll(_defaultRoles);
    _loadPersistedState();
    _initialized = true;
    notifyListeners();
  }

  Future<void> setRoleEnabled(String id, bool enabled) async {
    final index = _roles.indexWhere((role) => role.id == id);
    if (index == -1) return;
    _roles[index] = _roles[index].copyWith(enabled: enabled);
    await _persistState();
    notifyListeners();
  }

  Future<void> upsertCustomRole(MobileCodeRole role) async {
    final normalized = role.copyWith(
      id: role.id.trim().isEmpty ? _newCustomRoleId() : role.id,
      builtIn: false,
      enabled: true,
    );
    final index = _roles.indexWhere((item) => item.id == normalized.id);
    if (index == -1) {
      _roles.add(normalized);
    } else {
      _roles[index] = normalized;
    }
    await _persistState();
    notifyListeners();
  }

  Future<void> removeCustomRole(String id) async {
    _roles.removeWhere((role) => role.id == id && !role.builtIn);
    await _persistState();
    notifyListeners();
  }

  Future<RoleProposal?> createProposalFromPrompt(
    String prompt,
    String runId,
    List<MobileCodeRole> enabledRoles,
  ) async {
    final promptText = prompt.trim();
    if (promptText.isEmpty) return null;
    final candidates = enabledRoles.isEmpty ? _defaultRoles : enabledRoles;
    final scored = candidates
        .map((role) => MapEntry(role, _scoreRoleForPrompt(promptText, role)))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final best = scored.isEmpty ? _defaultRoles.first : scored.first.key;
    final bestScore = scored.isEmpty ? 0 : scored.first.value;
    if (bestScore >= 3) return null;

    final title = _titleFromIntent(promptText);
    final proposedRole = best.copyWith(
      id: _newCustomRoleId(),
      name: title.length <= 24 ? title : '${title.substring(0, 24)}...',
      summary: 'Suggested role for this task. Pending approval.',
      mission: _compact(promptText, 120),
      personality: '${best.personality} Adapt the role to this concrete user task.',
      responsibilities: [
        ...best.responsibilities.take(2),
        'Own this task-specific workflow until the result is explainable.',
        'Convert lessons from this run into a reusable role card if approved.',
      ],
      guardrails: [
        ...best.guardrails.take(2),
        'Do not become a parallel agent; stay inside the RR single execution lane.',
      ],
      successCriteria: [
        ...best.successCriteria.take(2),
        'The user can decide whether this role is worth saving.',
      ],
      promptTemplate:
          'You are a task-specific MobileCode role derived from ${best.name}. Focus on: ${_compact(promptText, 180)}. Keep work bounded, mobile-first, and verifiable.',
      builtIn: false,
      enabled: true,
    );
    final proposal = RoleProposal(
      proposalId: _newRoleProposalId(),
      sourceRoleId: best.id,
      role: proposedRole,
      prompt: _compact(promptText, 360),
      rationale:
          'No enabled role matched this prompt strongly enough. MobileCode adapted ${best.name} for this run; save it only if this specialty should be reused.',
      runId: runId,
      status: RoleProposalStatus.pending,
      createdAt: DateTime.now(),
    );
    _proposals.insert(0, proposal);
    _trimProposals();
    await _persistState();
    notifyListeners();
    return proposal;
  }

  Future<void> acceptProposal(String proposalId, {MobileCodeRole? editedRole}) async {
    final index = _proposals.indexWhere((proposal) => proposal.proposalId == proposalId);
    if (index == -1) return;
    final proposal = _proposals[index];
    await upsertCustomRole((editedRole ?? proposal.role).copyWith(builtIn: false, enabled: true));
    _proposals[index] = proposal.copyWith(status: RoleProposalStatus.accepted);
    await _persistState();
    notifyListeners();
  }

  Future<void> dismissProposal(String proposalId) async {
    final index = _proposals.indexWhere((proposal) => proposal.proposalId == proposalId);
    if (index == -1) return;
    _proposals[index] = _proposals[index].copyWith(status: RoleProposalStatus.dismissed);
    await _persistState();
    notifyListeners();
  }

  MobileCodeRole standardizeLocalIntent(String intent) {
    final compact = _compact(intent, 72);
    final title = _titleFromIntent(compact);
    final mission = compact.isEmpty
        ? 'Turn a rough mobile coding task into a bounded, testable contribution.'
        : compact;
    return MobileCodeRole(
      id: _newCustomRoleId(),
      name: title,
      summary: 'Custom role standardized from your intent.',
      mission: mission,
      personality: 'Calm, explicit, mobile-first, and biased toward small verifiable steps.',
      responsibilities: const [
        'Clarify the user intent before changing code.',
        'Keep edits scoped to the requested product surface.',
        'Explain failures with a concrete recovery action.',
      ],
      guardrails: const [
        'Do not invent platform capabilities.',
        'Do not run destructive commands without explicit confirmation.',
      ],
      successCriteria: const [
        'The output has a clear owner and acceptance criteria.',
        'The next action can be verified on phone or CI.',
      ],
      promptTemplate:
          'You are this MobileCode role inside a single execution lane. Own the requested scope, keep the work mobile-first, and return concrete implementation guidance with risks and verification steps.',
      avatarAsset: defaultCustomAvatarAsset,
      colorValue: 0xFF7557E8,
    );
  }

  MobileCodeRole parsePolishedOutput(String output, {String fallbackIntent = ''}) {
    final jsonText = _extractJsonObject(output);
    if (jsonText == null) return standardizeLocalIntent(fallbackIntent);
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) return standardizeLocalIntent(fallbackIntent);
      final fallback = standardizeLocalIntent(fallbackIntent);
      return MobileCodeRole(
        id: _newCustomRoleId(),
        name: _nonEmpty(decoded['name'], fallback.name),
        summary: _nonEmpty(decoded['summary'], fallback.summary),
        mission: _nonEmpty(decoded['mission'], fallback.mission),
        personality: _nonEmpty(decoded['personality'], fallback.personality),
        responsibilities: _stringList(decoded['responsibilities']).isEmpty
            ? fallback.responsibilities
            : _stringList(decoded['responsibilities']),
        guardrails: _stringList(decoded['guardrails']).isEmpty
            ? fallback.guardrails
            : _stringList(decoded['guardrails']),
        successCriteria: _stringList(decoded['successCriteria']).isEmpty
            ? fallback.successCriteria
            : _stringList(decoded['successCriteria']),
        promptTemplate: _nonEmpty(decoded['promptTemplate'], fallback.promptTemplate),
        avatarAsset: defaultCustomAvatarAsset,
        colorValue: fallback.colorValue,
      );
    } catch (_) {
      return standardizeLocalIntent(fallbackIntent);
    }
  }

  void _loadPersistedState() {
    final disabledIds = (_prefs?.getStringList(_disabledRoleIdsKey) ?? const <String>[]).toSet();
    for (var index = 0; index < _roles.length; index++) {
      final role = _roles[index];
      _roles[index] = role.copyWith(enabled: !disabledIds.contains(role.id));
    }

    final rawCustomRoles = _prefs?.getString(_customRolesKey);
    if (rawCustomRoles == null || rawCustomRoles.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(rawCustomRoles);
      if (decoded is List) {
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            _roles.add(MobileCodeRole.fromJson(item).copyWith(builtIn: false));
          }
        }
      }
    } catch (error) {
      debugPrint('[RoleLibrary] Failed to load custom roles: $error');
    }

    final rawProposals = _prefs?.getString(_roleProposalsKey);
    if (rawProposals == null || rawProposals.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(rawProposals);
      if (decoded is List) {
        _proposals
          ..clear()
          ..addAll(
            decoded
                .whereType<Map>()
                .map((item) => RoleProposal.fromJson(Map<String, dynamic>.from(item))),
          );
        _trimProposals();
      }
    } catch (error) {
      debugPrint('[RoleLibrary] Failed to load role proposals: $error');
    }
  }

  Future<void> _persistState() async {
    final customRoles = _roles.where((role) => !role.builtIn).map((role) => role.toJson()).toList();
    final disabledBuiltIns = _roles
        .where((role) => role.builtIn && !role.enabled)
        .map((role) => role.id)
        .toList(growable: false);
    await _prefs?.setString(_customRolesKey, jsonEncode(customRoles));
    await _prefs?.setStringList(_disabledRoleIdsKey, disabledBuiltIns);
    await _prefs?.setString(_roleProposalsKey, jsonEncode(_proposals.map((proposal) => proposal.toJson()).toList()));
  }

  void _trimProposals() {
    _proposals.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (_proposals.length > 30) {
      _proposals.removeRange(30, _proposals.length);
    }
  }
}

String _newCustomRoleId() => 'custom_${DateTime.now().microsecondsSinceEpoch}';

String _newRoleProposalId() => 'proposal_${DateTime.now().microsecondsSinceEpoch}';

String _nonEmpty(Object? value, String fallback) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? fallback : text;
}

List<String> _stringList(Object? value) {
  if (value is List) {
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
  if (value is String && value.trim().isNotEmpty) {
    return value
        .split(RegExp(r'[\n,;]'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
  return const [];
}

String? _extractJsonObject(String output) {
  final fenced = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(output)?.group(1);
  final source = fenced ?? output;
  final start = source.indexOf('{');
  final end = source.lastIndexOf('}');
  if (start == -1 || end <= start) return null;
  return source.substring(start, end + 1);
}

String _compact(String value, int limit) {
  final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.length <= limit) return normalized;
  return '${normalized.substring(0, limit - 1)}…';
}

String _titleFromIntent(String intent) {
  if (intent.isEmpty) return 'Custom Builder';
  final cleaned = intent.replaceAll(RegExp('[^\\w\\s\u4e00-\u9fff-]'), ' ').trim();
  final words = cleaned.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).take(3);
  final title = words.map((word) => word[0].toUpperCase() + word.substring(1)).join(' ');
  if (title.isNotEmpty) return title;
  return intent.length <= 10 ? intent : '${intent.substring(0, 10)}...';
}

int _scoreRoleForPrompt(String prompt, MobileCodeRole role) {
  final haystack = [
    prompt.toLowerCase(),
    if (prompt.contains('网页')) ' web html mobile_web_builder ',
    if (prompt.contains('界面') || prompt.contains('设计') || prompt.contains('布局')) ' ui designer ',
    if (prompt.contains('发布') || prompt.contains('部署')) ' release publish pages ',
    if (prompt.contains('运行') || prompt.contains('构建') || prompt.contains('终端')) ' runtime build shell ',
    if (prompt.contains('无障碍') || prompt.contains('可访问')) ' accessibility ',
  ].join(' ');
  final roleText = [
    role.id,
    role.name,
    role.summary,
    role.mission,
    role.personality,
    ...role.responsibilities,
    ...role.guardrails,
    ...role.successCriteria,
  ].join(' ').toLowerCase();
  final tokens = roleText
      .split(RegExp(r'[^a-z0-9_+#.-]+'))
      .where((token) => token.length >= 4)
      .toSet();
  var score = 0;
  for (final token in tokens) {
    if (haystack.contains(token)) score++;
  }
  if (role.id.contains('github') && haystack.contains('github')) score += 3;
  if (role.id.contains('web') && (haystack.contains('html') || haystack.contains('web'))) score += 2;
  if (role.id.contains('runtime') && (haystack.contains('runtime') || haystack.contains('build'))) score += 2;
  if (role.id.contains('release') && (haystack.contains('publish') || haystack.contains('pages'))) score += 2;
  return score;
}

const _defaultRoles = <MobileCodeRole>[
  MobileCodeRole(
    id: 'planner',
    name: 'Planner',
    summary: 'Breaks a request into the smallest useful mobile coding plan.',
    mission: 'Clarify the request and choose the safest build path.',
    personality: 'Structured, skeptical, and practical.',
    responsibilities: [
      'Clarify scope and stop line.',
      'Pick the next smallest verifiable step.',
      'Name risks before implementation.',
    ],
    guardrails: [
      'No speculative platform expansion.',
      'No unrelated refactors.',
    ],
    successCriteria: [
      'The task has a concrete next action.',
      'The user can understand why this path matters.',
    ],
    promptTemplate:
        'You are Planner inside one MobileCode execution lane. Clarify the goal, reduce scope, and propose the smallest verifiable action.',
    avatarAsset: 'assets/role_avatars/avatar-batch2-01-mist-studio.svg',
    colorValue: 0xFF7557E8,
    builtIn: true,
  ),
  MobileCodeRole(
    id: 'ui_designer',
    name: 'UI Designer',
    summary: 'Keeps generated HTML and app UI polished on phone screens.',
    mission: 'Keep the generated web page mobile-first and visually polished.',
    personality: 'Tasteful, precise, and allergic to cramped layouts.',
    responsibilities: [
      'Protect mobile spacing and touch targets.',
      'Choose coherent visual hierarchy.',
      'Flag overflow and unclear affordances.',
    ],
    guardrails: [
      'No decorative clutter that hides content.',
      'No unreadable small-screen text.',
    ],
    successCriteria: [
      'The UI works at 360dp width.',
      'Primary actions are visible and tappable.',
    ],
    promptTemplate:
        'You are UI Designer inside one MobileCode execution lane. Make the UI mobile-first, legible, and visually coherent.',
    avatarAsset: 'assets/role_avatars/avatar-batch2-02-office-glasses.svg',
    colorValue: 0xFFB7791F,
    builtIn: true,
  ),
  MobileCodeRole(
    id: 'mobile_web_builder',
    name: 'Mobile Web Builder',
    summary: 'Builds self-contained HTML artifacts that preview well in WebView.',
    mission: 'Write the local HTML artifact and keep it self-contained.',
    personality: 'Fast, concrete, and implementation-minded.',
    responsibilities: [
      'Generate portable index.html files.',
      'Avoid private path leaks in generated pages.',
      'Keep code readable enough for phone inspection.',
    ],
    guardrails: [
      'No hidden external dependencies unless requested.',
      'No desktop-only interaction model.',
    ],
    successCriteria: [
      'The artifact opens in WebView and browser.',
      'The code can be copied or published.',
    ],
    promptTemplate:
        'You are Mobile Web Builder inside one MobileCode execution lane. Produce self-contained, previewable HTML that works on mobile.',
    avatarAsset: 'assets/role_avatars/avatar-batch2-09-blue-cap.svg',
    colorValue: 0xFF16B9C7,
    builtIn: true,
  ),
  MobileCodeRole(
    id: 'runtime_reviewer',
    name: 'Runtime Reviewer',
    summary: 'Checks runtime paths, provider state, and recovery hints.',
    mission: 'Check file paths, previewability, and recovery hints.',
    personality: 'Calm, diagnostic, and explicit about constraints.',
    responsibilities: [
      'Explain missing runtime capabilities.',
      'Verify file/folder actions stay in workspace.',
      'Turn errors into next-step recovery guidance.',
    ],
    guardrails: [
      'No unsafe shell escalation.',
      'No silent fallback that hides failure.',
    ],
    successCriteria: [
      'Failures have a user-facing cause.',
      'Recovery actions are visible.',
    ],
    promptTemplate:
        'You are Runtime Reviewer inside one MobileCode execution lane. Diagnose runtime state, paths, and safe recovery steps.',
    avatarAsset: 'assets/role_avatars/avatar-batch2-15-tech.svg',
    colorValue: 0xFF0B9B7E,
    builtIn: true,
  ),
  MobileCodeRole(
    id: 'release_checker',
    name: 'Release Checker',
    summary: 'Prepares a result for sharing, Pages publish, and QA.',
    mission: 'Prepare the result for browser preview and GitHub Pages.',
    personality: 'Release-minded, concise, and evidence-driven.',
    responsibilities: [
      'Check publish readiness.',
      'Surface code URL, Pages URL, and local file path.',
      'Record verification evidence.',
    ],
    guardrails: [
      'No release claim without an artifact.',
      'No hiding permission or token failures.',
    ],
    successCriteria: [
      'The user can open the work and repo.',
      'The result has a clear verification status.',
    ],
    promptTemplate:
        'You are Release Checker inside one MobileCode execution lane. Turn completed work into shareable, verifiable output.',
    avatarAsset: 'assets/role_avatars/avatar-batch2-18-pencil-wash.svg',
    colorValue: 0xFF2555FF,
    builtIn: true,
  ),
  MobileCodeRole(
    id: 'accessibility_auditor',
    name: 'Accessibility Auditor',
    summary: 'Reviews generated pages for basic semantic and touch accessibility.',
    mission: 'Find accessibility blockers before preview or publish.',
    personality: 'Careful, inclusive, and specific.',
    responsibilities: [
      'Check headings, alt text, labels, and focus states.',
      'Flag low contrast and tiny tap targets.',
      'Suggest minimal fixes.',
    ],
    guardrails: [
      'No cosmetic-only accessibility claims.',
      'No inaccessible icon-only controls without labels.',
    ],
    successCriteria: [
      'Core actions have readable labels.',
      'Warnings are actionable.',
    ],
    promptTemplate:
        'You are Accessibility Auditor inside one MobileCode execution lane. Review mobile web output for semantic, touch, and readability issues.',
    avatarAsset: 'assets/role_avatars/avatar-batch2-21-navy.svg',
    colorValue: 0xFF4F8F2D,
    builtIn: true,
  ),
  MobileCodeRole(
    id: 'github_publisher',
    name: 'GitHub Publisher',
    summary: 'Owns repository, Pages, Actions, and artifact status details.',
    mission: 'Keep GitHub operations understandable and recoverable.',
    personality: 'Operational, exact, and permission-aware.',
    responsibilities: [
      'Map token errors to recovery actions.',
      'Connect local artifacts to repos and Pages URLs.',
      'Explain Actions and artifact state.',
    ],
    guardrails: [
      'No broad token advice without scope details.',
      'No destructive repo changes without confirmation.',
    ],
    successCriteria: [
      'GitHub failures name the missing permission.',
      'Publish success includes Pages and repo links.',
    ],
    promptTemplate:
        'You are GitHub Publisher inside one MobileCode execution lane. Make repo, Pages, Actions, and artifact workflows clear and reversible.',
    avatarAsset: 'assets/role_avatars/avatar-batch2-23-mono.svg',
    colorValue: 0xFF0B1020,
    builtIn: true,
  ),
  MobileCodeRole(
    id: 'prompt_refiner',
    name: 'Prompt Refiner',
    summary: 'Turns vague app ideas into buildable MobileCode instructions.',
    mission: 'Convert user intent into a crisp implementation prompt.',
    personality: 'Curious, compact, and product-aware.',
    responsibilities: [
      'Extract the product goal.',
      'Add constraints the agent needs to build safely.',
      'Preserve the user’s intent and tone.',
    ],
    guardrails: [
      'No over-specifying beyond the user’s ask.',
      'No hidden feature expansion.',
    ],
    successCriteria: [
      'The prompt is buildable in one pass.',
      'The user can recognize their original idea.',
    ],
    promptTemplate:
        'You are Prompt Refiner inside one MobileCode execution lane. Make rough requests precise without changing the user’s intent.',
    avatarAsset: 'assets/role_avatars/avatar-batch2-35-yellow-bucket.svg',
    colorValue: 0xFFE0526E,
    builtIn: true,
  ),
];
