import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/github_repo.dart';
import 'github_repo_hub_service.dart';
import 'memory_service.dart';
import 'role_library_service.dart';

const _digestDefaultBaseUrl = 'https://token-plan-cn.xiaomimimo.com/anthropic';
const _digestDefaultModel = 'mimo-v2.5-pro';
const _digestManagedProviderEnabled = bool.fromEnvironment('MOBILECODE_MANAGED_PROVIDER');
const _digestManagedBaseUrl = String.fromEnvironment(
  'MOBILECODE_MANAGED_BASE_URL',
  defaultValue: _digestDefaultBaseUrl,
);
const _digestManagedModel = String.fromEnvironment(
  'MOBILECODE_MANAGED_MODEL',
  defaultValue: _digestDefaultModel,
);
const _digestManagedApiKey = String.fromEnvironment('MOBILECODE_MANAGED_API_KEY');

const _digestBaseUrlKey = 'mobilecode.baseUrl';
const _digestApiKeyKey = 'mobilecode.apiKey';
const _digestModelKey = 'mobilecode.model';
const _digestProviderModeKey = 'mobilecode.providerMode';

const repoKnowledgeDigestSystemPrompt = '''
You are MobileCode Repo Intelligence.

Analyze repository metadata and README snippets, then suggest only practical
MobileCode roles and Memory rules. Return JSON only, no markdown fences.

Schema:
{
  "summary": "2 concise sentences",
  "techStacks": ["Dart", "GitHub Actions"],
  "projectTypes": ["mobile app", "HTML demo"],
  "roleSuggestions": [
    {
      "name": "2-4 words",
      "summary": "one short sentence",
      "mission": "what this role owns in one MobileCode execution lane",
      "personality": "working style and tone",
      "responsibilities": ["3-5 concrete responsibilities"],
      "guardrails": ["2-4 boundaries"],
      "successCriteria": ["2-4 observable criteria"],
      "promptTemplate": "system-style role prompt written in second person",
      "rationale": "why this role is needed",
      "evidenceRepos": ["owner/repo"]
    }
  ],
  "memoryRules": [
    {
      "title": "short title",
      "category": "preference|workflow|stack|release|naming",
      "rule": "one durable rule",
      "rationale": "why this belongs in app memory",
      "evidenceRepos": ["owner/repo"]
    }
  ]
}

Rules:
- Do not mention secrets, tokens, or private config.
- Do not ask to scan full source code.
- Prefer mobile coding, GitHub Pages, Actions, release QA, Runtime, Skill/MCP
  curation, and HTML/UI roles.
- Every suggestion must include evidenceRepos.
- If evidence is thin, return fewer suggestions.
''';

const memoryRulePolishSystemPrompt = '''
You are MobileCode Memory Rule Standardizer.

Turn a rough user-edited memory rule into one durable MobileCode memory rule.
Return JSON only, no markdown fences.

Schema:
{
  "title": "short title",
  "category": "preference|workflow|stack|release|naming|repo-insight",
  "rule": "one clear durable rule"
}

Rules:
- Keep the rule about durable user preferences, engineering norms, repository
  workflow, release process, naming, or mobile runtime constraints.
- Do not store secrets, tokens, URLs with credentials, or one-off task details.
- The rule must be useful in future MobileCode sessions.
- Prefer one concise sentence for "rule".
''';

enum _DigestProviderFlavor { openAi, anthropic }

@immutable
class RepoReadmeSample {
  const RepoReadmeSample({
    required this.repo,
    required this.readme,
    required this.watched,
  });

  final GitHubRepo repo;
  final String readme;
  final bool watched;
}

@immutable
class RepoKnowledgeDigest {
  const RepoKnowledgeDigest({
    required this.summary,
    required this.techStacks,
    required this.projectTypes,
    required this.roleProposals,
    required this.memoryProposals,
    required this.analyzedRepos,
    required this.source,
    this.fallbackReason,
  });

  final String summary;
  final List<String> techStacks;
  final List<String> projectTypes;
  final List<RoleProposal> roleProposals;
  final List<MemoryRuleProposal> memoryProposals;
  final List<String> analyzedRepos;
  final String source;
  final String? fallbackReason;

  bool get usedProvider => source == 'provider';
}

@immutable
class RolePolishResult {
  const RolePolishResult({
    required this.role,
    required this.usedProvider,
    this.fallbackReason,
  });

  final MobileCodeRole role;
  final bool usedProvider;
  final String? fallbackReason;
}

@immutable
class MemoryRulePolishResult {
  const MemoryRulePolishResult({
    required this.rule,
    required this.usedProvider,
    this.fallbackReason,
  });

  final MemoryRule rule;
  final bool usedProvider;
  final String? fallbackReason;
}

class RepoKnowledgeDigestService {
  Future<RepoKnowledgeDigest> analyzeWatchedAndOwnerRepos(GitHubRepoHubService hub) async {
    await hub.initialize();
    if (!hub.isAuthenticated) {
      throw StateError('GitHub access is required to analyze owner repositories.');
    }

    final repos = await _selectRepos(hub);
    final samples = await _loadReadmeSamples(hub, repos);
    final fallback = _heuristicDigest(samples, fallbackReason: 'Provider is not configured.');
    if (samples.isEmpty) return fallback;

    final config = await _loadProviderConfig();
    if (config == null) return fallback;

    final flavor = _detectFlavor(config.baseUrl, config.model);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client
          .postUrl(flavor == _DigestProviderFlavor.anthropic
              ? _anthropicMessagesUri(config.baseUrl)
              : _openAiChatUri(config.baseUrl))
          .timeout(const Duration(seconds: 10));
      request.headers.contentType = ContentType.json;
      if (flavor == _DigestProviderFlavor.anthropic) {
        request.headers.set('anthropic-version', '2023-06-01');
        request.headers.set('x-api-key', config.apiKey);
      }
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${config.apiKey}');
      request.write(jsonEncode(_requestBody(flavor, config.model, samples)));

      final response = await request.close().timeout(const Duration(seconds: 70));
      final body = await utf8.decodeStream(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return fallback.copyWith(fallbackReason: 'Provider HTTP ${response.statusCode}.');
      }
      final text = _extractProviderText(body).trim();
      if (text.isEmpty) {
        return fallback.copyWith(
          fallbackReason: 'AI provider returned an empty response; local heuristic suggestions are shown.',
        );
      }
      try {
        return _parseDigest(text, samples, fallback);
      } on FormatException {
        return fallback.copyWith(
          fallbackReason: 'AI provider response was not structured JSON; local heuristic suggestions are shown.',
        );
      }
    } on TimeoutException {
      return fallback.copyWith(fallbackReason: 'Provider timed out; heuristic suggestions shown.');
    } on SocketException catch (error) {
      return fallback.copyWith(fallbackReason: _friendlySocketError(error));
    } on Object catch (error) {
      return fallback.copyWith(fallbackReason: _compact(error.toString(), 140));
    } finally {
      client.close(force: true);
    }
  }

  List<RoleProposal> buildRoleProposals(RepoKnowledgeDigest digest) => digest.roleProposals;

  List<MemoryRuleProposal> buildMemoryRuleProposals(RepoKnowledgeDigest digest) => digest.memoryProposals;

  Future<RolePolishResult> polishRole(MobileCodeRole draft) async {
    final fallback = _fallbackPolishedRole(draft);
    final config = await _loadProviderConfig();
    if (config == null) {
      return RolePolishResult(
        role: fallback,
        usedProvider: false,
        fallbackReason: 'Provider is not configured; used local role template.',
      );
    }

    try {
      final text = await _completeWithProvider(
        config: config,
        systemPrompt: rolePolishSystemPrompt,
        userPrompt: _rolePolishPrompt(draft),
        maxTokens: 1200,
      );
      final polished = RoleLibraryService.instance
          .parsePolishedOutput(text, fallbackIntent: _roleIntent(draft))
          .copyWith(
            id: draft.id,
            avatarAsset: draft.avatarAsset,
            colorValue: draft.colorValue,
            builtIn: false,
            enabled: true,
          );
      return RolePolishResult(role: polished, usedProvider: true);
    } on TimeoutException {
      return RolePolishResult(
        role: fallback,
        usedProvider: false,
        fallbackReason: 'Provider timed out; used local role template.',
      );
    } on SocketException catch (error) {
      return RolePolishResult(
        role: fallback,
        usedProvider: false,
        fallbackReason: _friendlySocketError(error),
      );
    } on Object catch (error) {
      return RolePolishResult(
        role: fallback,
        usedProvider: false,
        fallbackReason: _compact(error.toString(), 140),
      );
    }
  }

  Future<MemoryRulePolishResult> polishMemoryRule(MemoryRule draft) async {
    final fallback = _fallbackPolishedMemoryRule(draft);
    final config = await _loadProviderConfig();
    if (config == null) {
      return MemoryRulePolishResult(
        rule: fallback,
        usedProvider: false,
        fallbackReason: 'Provider is not configured; used local memory template.',
      );
    }

    try {
      final text = await _completeWithProvider(
        config: config,
        systemPrompt: memoryRulePolishSystemPrompt,
        userPrompt: _memoryRulePolishPrompt(draft),
        maxTokens: 500,
      );
      final polished = _parseMemoryRulePolish(text, fallback);
      return MemoryRulePolishResult(rule: polished, usedProvider: true);
    } on TimeoutException {
      return MemoryRulePolishResult(
        rule: fallback,
        usedProvider: false,
        fallbackReason: 'Provider timed out; used local memory template.',
      );
    } on SocketException catch (error) {
      return MemoryRulePolishResult(
        rule: fallback,
        usedProvider: false,
        fallbackReason: _friendlySocketError(error),
      );
    } on Object catch (error) {
      return MemoryRulePolishResult(
        rule: fallback,
        usedProvider: false,
        fallbackReason: _compact(error.toString(), 140),
      );
    }
  }

  Future<List<GitHubRepo>> _selectRepos(GitHubRepoHubService hub) async {
    final watchlist = await hub.loadWatchlist();
    final byKey = <String, GitHubRepo>{};

    for (final key in watchlist.take(25)) {
      final parts = key.split('/');
      if (parts.length != 2) continue;
      try {
        final repo = await hub.github.getRepository(parts[0], parts[1], public: true);
        byKey[GitHubRepoHubService.repoKey(repo)] = repo;
      } on Object catch (error) {
        debugPrint('[RepoDigest] Skipping watched repo $key: $error');
      }
    }

    final ownerItems = await hub.loadHubItems(owner: hub.currentUser, sort: 'pushed');
    for (final item in ownerItems) {
      byKey.putIfAbsent(item.key, () => item.repo);
      if (byKey.length >= 25) break;
    }

    final watchedFirst = <GitHubRepo>[];
    final rest = <GitHubRepo>[];
    for (final repo in byKey.values) {
      if (watchlist.contains(GitHubRepoHubService.repoKey(repo))) {
        watchedFirst.add(repo);
      } else {
        rest.add(repo);
      }
    }
    watchedFirst.sort((a, b) => b.pushedAt.compareTo(a.pushedAt));
    rest.sort((a, b) => b.pushedAt.compareTo(a.pushedAt));
    return [...watchedFirst, ...rest].take(25).toList(growable: false);
  }

  Future<List<RepoReadmeSample>> _loadReadmeSamples(
    GitHubRepoHubService hub,
    List<GitHubRepo> repos,
  ) async {
    final watchlist = await hub.loadWatchlist();
    final samples = <RepoReadmeSample>[];
    var totalChars = 0;
    for (final repo in repos) {
      if (totalChars >= 80000) break;
      try {
        final readme = await hub.github.getReadmeContent(
          repo.owner,
          repo.name,
          public: !repo.isPrivate,
        );
        final snippet = _compact(readme, 6000);
        if (snippet.trim().isEmpty && repo.description.trim().isEmpty) continue;
        totalChars += snippet.length;
        samples.add(RepoReadmeSample(
          repo: repo,
          readme: snippet,
          watched: watchlist.contains(GitHubRepoHubService.repoKey(repo)),
        ));
      } on Object catch (error) {
        debugPrint('[RepoDigest] README failed for ${repo.fullName}: $error');
      }
    }
    return samples;
  }

  Future<_DigestProviderConfig?> _loadProviderConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final useManaged = _digestManagedProviderEnabled && prefs.getString(_digestProviderModeKey) != 'custom';
    final baseUrl = useManaged ? _digestManagedBaseUrl : _savedOrDefault(prefs.getString(_digestBaseUrlKey), _digestDefaultBaseUrl);
    final apiKey = useManaged ? _digestManagedApiKey : (prefs.getString(_digestApiKeyKey) ?? '');
    final model = useManaged ? _digestManagedModel : _savedOrDefault(prefs.getString(_digestModelKey), _digestDefaultModel);
    if (baseUrl.trim().isEmpty || apiKey.trim().isEmpty) return null;
    return _DigestProviderConfig(baseUrl: baseUrl.trim(), apiKey: apiKey.trim(), model: model.trim());
  }

  Future<String> _completeWithProvider({
    required _DigestProviderConfig config,
    required String systemPrompt,
    required String userPrompt,
    required int maxTokens,
  }) async {
    final flavor = _detectFlavor(config.baseUrl, config.model);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client
          .postUrl(flavor == _DigestProviderFlavor.anthropic
              ? _anthropicMessagesUri(config.baseUrl)
              : _openAiChatUri(config.baseUrl))
          .timeout(const Duration(seconds: 10));
      request.headers.contentType = ContentType.json;
      if (flavor == _DigestProviderFlavor.anthropic) {
        request.headers.set('anthropic-version', '2023-06-01');
        request.headers.set('x-api-key', config.apiKey);
      }
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${config.apiKey}');
      request.write(jsonEncode(_completionRequestBody(
        flavor: flavor,
        model: config.model,
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        maxTokens: maxTokens,
      )));

      final response = await request.close().timeout(const Duration(seconds: 70));
      final body = await utf8.decodeStream(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Provider HTTP ${response.statusCode}: ${_compact(body, 180)}');
      }
      final text = _extractProviderText(body);
      if (text.trim().isEmpty) {
        throw const FormatException('Provider returned an empty response.');
      }
      return text;
    } finally {
      client.close(force: true);
    }
  }

  Map<String, dynamic> _completionRequestBody({
    required _DigestProviderFlavor flavor,
    required String model,
    required String systemPrompt,
    required String userPrompt,
    required int maxTokens,
  }) {
    final resolvedModel = model.isEmpty ? (flavor == _DigestProviderFlavor.anthropic ? _digestDefaultModel : 'gpt-4o-mini') : model;
    if (flavor == _DigestProviderFlavor.anthropic) {
      return {
        'model': resolvedModel,
        'system': systemPrompt,
        'max_tokens': maxTokens,
        'temperature': 0.2,
        'messages': [
          {'role': 'user', 'content': userPrompt},
        ],
      };
    }
    return {
      'model': resolvedModel,
      'temperature': 0.2,
      'response_format': {'type': 'json_object'},
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ],
    };
  }

  Map<String, dynamic> _requestBody(
    _DigestProviderFlavor flavor,
    String model,
    List<RepoReadmeSample> samples,
  ) {
    final content = _samplesPrompt(samples);
    final resolvedModel = model.isEmpty ? (flavor == _DigestProviderFlavor.anthropic ? _digestDefaultModel : 'gpt-4o-mini') : model;
    if (flavor == _DigestProviderFlavor.anthropic) {
      return {
        'model': resolvedModel,
        'system': repoKnowledgeDigestSystemPrompt,
        'max_tokens': 1800,
        'temperature': 0.2,
        'messages': [
          {'role': 'user', 'content': content},
        ],
      };
    }
    return {
      'model': resolvedModel,
      'temperature': 0.2,
      'response_format': {'type': 'json_object'},
      'messages': [
        {'role': 'system', 'content': repoKnowledgeDigestSystemPrompt},
        {'role': 'user', 'content': content},
      ],
    };
  }
}

extension on RepoKnowledgeDigest {
  RepoKnowledgeDigest copyWith({
    String? summary,
    List<String>? techStacks,
    List<String>? projectTypes,
    List<RoleProposal>? roleProposals,
    List<MemoryRuleProposal>? memoryProposals,
    List<String>? analyzedRepos,
    String? source,
    String? fallbackReason,
  }) {
    return RepoKnowledgeDigest(
      summary: summary ?? this.summary,
      techStacks: techStacks ?? this.techStacks,
      projectTypes: projectTypes ?? this.projectTypes,
      roleProposals: roleProposals ?? this.roleProposals,
      memoryProposals: memoryProposals ?? this.memoryProposals,
      analyzedRepos: analyzedRepos ?? this.analyzedRepos,
      source: source ?? this.source,
      fallbackReason: fallbackReason ?? this.fallbackReason,
    );
  }
}

class _DigestProviderConfig {
  const _DigestProviderConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });

  final String baseUrl;
  final String apiKey;
  final String model;
}

MobileCodeRole _fallbackPolishedRole(MobileCodeRole draft) {
  final local = RoleLibraryService.instance.standardizeLocalIntent(_roleIntent(draft));
  return local.copyWith(
    id: draft.id,
    name: draft.name.trim().isEmpty ? local.name : _compact(draft.name, 40),
    summary: draft.summary.trim().isEmpty ? local.summary : _compact(draft.summary, 120),
    mission: draft.mission.trim().isEmpty ? local.mission : _compact(draft.mission, 260),
    personality: draft.personality.trim().isEmpty ? local.personality : _compact(draft.personality, 180),
    responsibilities: draft.responsibilities.where((item) => item.trim().isNotEmpty).take(5).toList().isEmpty
        ? local.responsibilities
        : draft.responsibilities.where((item) => item.trim().isNotEmpty).take(5).toList(),
    guardrails: draft.guardrails.where((item) => item.trim().isNotEmpty).take(4).toList().isEmpty
        ? local.guardrails
        : draft.guardrails.where((item) => item.trim().isNotEmpty).take(4).toList(),
    successCriteria: draft.successCriteria.where((item) => item.trim().isNotEmpty).take(4).toList().isEmpty
        ? local.successCriteria
        : draft.successCriteria.where((item) => item.trim().isNotEmpty).take(4).toList(),
    promptTemplate: draft.promptTemplate.trim().isEmpty ? local.promptTemplate : _compact(draft.promptTemplate, 900),
    avatarAsset: draft.avatarAsset,
    colorValue: draft.colorValue,
    builtIn: false,
    enabled: true,
  );
}

MemoryRule _fallbackPolishedMemoryRule(MemoryRule draft) {
  final rule = _compact(draft.rule.trim().isEmpty ? 'Use repository evidence before making durable MobileCode decisions.' : draft.rule, 420);
  final title = draft.title.trim().isEmpty ? _titleFromRule(rule) : _compact(draft.title, 70);
  final category = _memoryCategory(draft.category);
  return draft.copyWith(
    title: title,
    category: category,
    rule: rule,
    source: draft.source.trim().isEmpty ? 'repo-knowledge-polish' : draft.source,
    enabled: true,
  );
}

String _rolePolishPrompt(MobileCodeRole draft) {
  return jsonEncode({
    'instruction': 'Standardize this user-edited MobileCode role. Preserve intent, improve structure, and keep it bounded.',
    'role': {
      'name': draft.name,
      'summary': draft.summary,
      'mission': draft.mission,
      'personality': draft.personality,
      'responsibilities': draft.responsibilities,
      'guardrails': draft.guardrails,
      'successCriteria': draft.successCriteria,
      'promptTemplate': draft.promptTemplate,
    },
  });
}

String _memoryRulePolishPrompt(MemoryRule draft) {
  return jsonEncode({
    'instruction': 'Standardize this user-edited MobileCode memory rule. Keep only durable future-use guidance.',
    'memoryRule': {
      'title': draft.title,
      'category': draft.category,
      'rule': draft.rule,
      'source': draft.source,
      'evidenceRepos': draft.evidenceRepos,
    },
  });
}

String _roleIntent(MobileCodeRole draft) {
  return [
    draft.name,
    draft.summary,
    draft.mission,
    draft.personality,
    ...draft.responsibilities,
    ...draft.guardrails,
    ...draft.successCriteria,
    draft.promptTemplate,
  ].where((item) => item.trim().isNotEmpty).join('\n');
}

MemoryRule _parseMemoryRulePolish(String text, MemoryRule fallback) {
  final jsonText = _extractJsonObject(text);
  if (jsonText == null) return fallback;
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map<String, dynamic>) return fallback;
  final rule = decoded['rule']?.toString().trim();
  return fallback.copyWith(
    title: _compact(_nonEmptyText(decoded['title'], fallback.title), 70),
    category: _memoryCategory(decoded['category']?.toString() ?? fallback.category),
    rule: rule == null || rule.isEmpty ? fallback.rule : _compact(rule, 420),
    enabled: true,
  );
}

String _nonEmptyText(Object? value, String fallback) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? fallback : text;
}

String _memoryCategory(String value) {
  final normalized = value.trim().toLowerCase();
  const allowed = {'preference', 'workflow', 'stack', 'release', 'naming', 'repo-insight'};
  return allowed.contains(normalized) ? normalized : 'repo-insight';
}

String _titleFromRule(String rule) {
  final normalized = rule.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.isEmpty) return 'Repo insight rule';
  final firstSentence = normalized.split(RegExp(r'[。.!?]')).first.trim();
  return _compact(firstSentence.isEmpty ? normalized : firstSentence, 70);
}

RepoKnowledgeDigest _parseDigest(
  String text,
  List<RepoReadmeSample> samples,
  RepoKnowledgeDigest fallback,
) {
  final jsonText = _extractJsonObject(text);
  if (jsonText == null) throw const FormatException('Provider did not return JSON.');
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map<String, dynamic>) throw const FormatException('Provider JSON is not an object.');

  final roleItems = (decoded['roleSuggestions'] as List<dynamic>?) ?? const [];
  final memoryItems = (decoded['memoryRules'] as List<dynamic>?) ?? const [];
  final roles = <RoleProposal>[];
  final rules = <MemoryRuleProposal>[];
  final now = DateTime.now();
  final evidenceFallback = samples.map((sample) => sample.repo.fullName).take(3).toList(growable: false);

  for (var i = 0; i < roleItems.length && roles.length < 5; i++) {
    final item = roleItems[i];
    if (item is! Map<String, dynamic>) continue;
    final name = _compact(item['name']?.toString() ?? 'Repo Specialist', 40);
    final evidence = _nonEmptyList(item['evidenceRepos']).isEmpty
        ? evidenceFallback
        : _nonEmptyList(item['evidenceRepos']).take(5).toList();
    roles.add(RoleProposal(
      proposalId: 'repo_role_${now.microsecondsSinceEpoch}_$i',
      sourceRoleId: 'repo-knowledge-digest',
      role: MobileCodeRole(
        id: 'repo_role_${now.microsecondsSinceEpoch}_$i',
        name: name,
        summary: _compact(item['summary']?.toString() ?? 'Repository-informed MobileCode role.', 120),
        mission: _compact(item['mission']?.toString() ?? 'Improve repository-specific MobileCode work.', 260),
        personality: _compact(item['personality']?.toString() ?? 'Careful, concrete, and mobile-aware.', 180),
        responsibilities: _nonEmptyList(item['responsibilities']).take(5).toList(),
        guardrails: _nonEmptyList(item['guardrails']).take(4).toList(),
        successCriteria: _nonEmptyList(item['successCriteria']).take(4).toList(),
        promptTemplate: _compact(item['promptTemplate']?.toString() ?? 'You adapt MobileCode work to repository evidence and mobile constraints.', 700),
        avatarAsset: RoleLibraryService.defaultCustomAvatarAsset,
        colorValue: 0xFF2555FF,
        builtIn: false,
        enabled: true,
      ),
      prompt: 'Repo evidence: ${evidence.join(', ')}',
      rationale: _compact(item['rationale']?.toString() ?? 'Suggested from README evidence.', 260),
      runId: 'repo_digest_${now.millisecondsSinceEpoch}',
      status: RoleProposalStatus.pending,
      createdAt: now,
    ));
  }

  for (var i = 0; i < memoryItems.length && rules.length < 8; i++) {
    final item = memoryItems[i];
    if (item is! Map<String, dynamic>) continue;
    final evidence = _nonEmptyList(item['evidenceRepos']).isEmpty
        ? evidenceFallback
        : _nonEmptyList(item['evidenceRepos']).take(5).toList();
    final rule = MemoryRule(
      id: 'repo_memory_${now.microsecondsSinceEpoch}_$i',
      title: _compact(item['title']?.toString() ?? 'Repo workflow rule', 70),
      category: _compact(item['category']?.toString() ?? 'repo-insight', 30),
      rule: _compact(item['rule']?.toString() ?? 'Prefer repository-specific workflows when generating code.', 400),
      source: 'repo-knowledge-digest',
      evidenceRepos: evidence,
      createdAt: now,
    );
    rules.add(MemoryRuleProposal(
      proposalId: 'repo_memory_proposal_${now.microsecondsSinceEpoch}_$i',
      rule: rule,
      rationale: _compact(item['rationale']?.toString() ?? 'Suggested from README evidence.', 260),
      evidenceRepos: evidence,
      status: MemoryRuleProposalStatus.pending,
      createdAt: now,
    ));
  }

  return RepoKnowledgeDigest(
    summary: _compact(decoded['summary']?.toString() ?? fallback.summary, 420),
    techStacks: _nonEmptyList(decoded['techStacks']).isEmpty ? fallback.techStacks : _nonEmptyList(decoded['techStacks']).take(10).toList(),
    projectTypes: _nonEmptyList(decoded['projectTypes']).isEmpty ? fallback.projectTypes : _nonEmptyList(decoded['projectTypes']).take(8).toList(),
    roleProposals: roles.isEmpty ? fallback.roleProposals : roles,
    memoryProposals: rules.isEmpty ? fallback.memoryProposals : rules,
    analyzedRepos: fallback.analyzedRepos,
    source: 'provider',
  );
}

RepoKnowledgeDigest _heuristicDigest(List<RepoReadmeSample> samples, {String? fallbackReason}) {
  final repos = samples.map((sample) => sample.repo.fullName).toList(growable: false);
  final text = samples.map((sample) => '${sample.repo.fullName}\n${sample.repo.description}\n${sample.readme}').join('\n').toLowerCase();
  final stacks = <String>{
    for (final sample in samples)
      if ((sample.repo.language ?? '').trim().isNotEmpty) sample.repo.language!.trim(),
    if (text.contains('flutter')) 'Flutter',
    if (text.contains('github actions') || text.contains('.github/workflows')) 'GitHub Actions',
    if (text.contains('pages') || text.contains('gh-pages')) 'GitHub Pages',
    if (text.contains('mcp')) 'MCP',
    if (text.contains('skill.md') || text.contains('skill.yaml')) 'Skills',
  }.toList()
    ..sort();
  final types = <String>{
    if (text.contains('mobile') || text.contains('android') || text.contains('ios')) 'mobile app',
    if (text.contains('html') || text.contains('webview') || text.contains('pages')) 'web demo',
    if (text.contains('release') || text.contains('apk') || text.contains('artifact')) 'release pipeline',
    if (text.contains('skill') || text.contains('mcp')) 'agent tooling',
  }.toList()
    ..sort();
  final evidence = repos.take(4).toList(growable: false);
  final now = DateTime.now();
  final roles = <RoleProposal>[];
  final rules = <MemoryRuleProposal>[];

  void addRole({
    required String name,
    required String summary,
    required String mission,
    required List<String> responsibilities,
  }) {
    final index = roles.length;
    roles.add(RoleProposal(
      proposalId: 'repo_role_${now.microsecondsSinceEpoch}_$index',
      sourceRoleId: 'repo-knowledge-heuristic',
      role: MobileCodeRole(
        id: 'repo_role_${now.microsecondsSinceEpoch}_$index',
        name: name,
        summary: summary,
        mission: mission,
        personality: 'Concise, evidence-driven, and careful about mobile runtime limits.',
        responsibilities: responsibilities,
        guardrails: const [
          'Do not infer secrets or private implementation details from README snippets.',
          'Prefer GitHub-backed workflows when local runtime is not available.',
        ],
        successCriteria: const [
          'Advice cites repository evidence.',
          'Actions are small enough for a phone-first workflow.',
        ],
        promptTemplate: 'You are a repository-informed MobileCode role. Use README evidence, keep work phone-friendly, and explain GitHub workflow tradeoffs.',
        avatarAsset: RoleLibraryService.defaultCustomAvatarAsset,
        colorValue: 0xFF0B9B7E,
        builtIn: false,
        enabled: true,
      ),
      prompt: 'Repo evidence: ${evidence.join(', ')}',
      rationale: 'Heuristic suggestion from repository languages, README keywords, and workflow hints.',
      runId: 'repo_digest_${now.millisecondsSinceEpoch}',
      status: RoleProposalStatus.pending,
      createdAt: now,
    ));
  }

  void addRule(String title, String category, String rule) {
    final index = rules.length;
    rules.add(MemoryRuleProposal(
      proposalId: 'repo_memory_proposal_${now.microsecondsSinceEpoch}_$index',
      rule: MemoryRule(
        id: 'repo_memory_${now.microsecondsSinceEpoch}_$index',
        title: title,
        category: category,
        rule: rule,
        source: 'repo-knowledge-heuristic',
        evidenceRepos: evidence,
        createdAt: now,
      ),
      rationale: 'Heuristic rule from repository README patterns.',
      evidenceRepos: evidence,
      status: MemoryRuleProposalStatus.pending,
      createdAt: now,
    ));
  }

  if (text.contains('pages') || text.contains('gh-pages') || text.contains('html')) {
    addRole(
      name: 'Pages Publisher',
      summary: 'Keeps HTML demos mobile-ready and GitHub Pages friendly.',
      mission: 'Own publish readiness, Pages constraints, and shareable output cards.',
      responsibilities: const [
        'Check title, viewport, and mobile layout before publishing.',
        'Prefer GitHub Pages for lightweight HTML demos.',
        'Explain Pages failures with actionable next steps.',
      ],
    );
    addRule('Prefer Pages for HTML demos', 'release', 'When a generated project is a lightweight HTML/web demo, prefer GitHub Pages publish over local heavy builds.');
  }
  if (text.contains('actions') || text.contains('workflow') || text.contains('artifact') || text.contains('apk')) {
    addRole(
      name: 'Actions Builder',
      summary: 'Moves heavy builds into GitHub Actions.',
      mission: 'Own workflow dispatch, artifact interpretation, and build failure summaries.',
      responsibilities: const [
        'Use Actions for APK or heavyweight build jobs.',
        'Surface artifact links and failed job summaries.',
        'Avoid requiring a full local compiler when GitHub can build remotely.',
      ],
    );
    addRule('Use Actions for heavy builds', 'workflow', 'For APK, Gradle, iOS archive, or release artifacts, prefer GitHub Actions and show artifact/download status in MobileCode.');
  }
  if (text.contains('skill') || text.contains('mcp')) {
    addRole(
      name: 'Skill Curator',
      summary: 'Reviews Skill/MCP repos before install.',
      mission: 'Own provenance checks, manifest review, and disabled-by-default MCP registration.',
      responsibilities: const [
        'Review manifest and source before installing skills.',
        'Register MCP candidates disabled by default.',
        'Flag unknown commands, network tools, and weak provenance.',
      ],
    );
    addRule('Review connectors first', 'preference', 'Skill and MCP repositories must be reviewed for manifest, command, provenance, and risk before installation or registration.');
  }
  if (roles.isEmpty) {
    addRole(
      name: 'Repo Reviewer',
      summary: 'Adapts MobileCode work to the user repository set.',
      mission: 'Summarize repo evidence and keep generated work aligned with existing stacks.',
      responsibilities: const [
        'Infer stack and workflow from README evidence.',
        'Recommend small phone-friendly next actions.',
        'Avoid broad claims when README evidence is thin.',
      ],
    );
  }
  if (rules.isEmpty) {
    addRule('Use repository evidence', 'workflow', 'When working inside a GitHub-linked chat, infer stack and release workflow from README evidence before making code or publish decisions.');
  }

  return RepoKnowledgeDigest(
    summary: samples.isEmpty
        ? 'No readable README evidence was found yet.'
        : 'Analyzed ${samples.length} repositories from watchlist and the active GitHub account. Suggestions are heuristic because the model provider was unavailable.',
    techStacks: stacks.isEmpty ? const ['GitHub'] : stacks.take(10).toList(),
    projectTypes: types.isEmpty ? const ['repository workspace'] : types.take(8).toList(),
    roleProposals: roles,
    memoryProposals: rules,
    analyzedRepos: repos,
    source: 'heuristic',
    fallbackReason: fallbackReason,
  );
}

String _samplesPrompt(List<RepoReadmeSample> samples) {
  final buffer = StringBuffer('Analyze these MobileCode user repositories. Do not infer secrets.\n\n');
  for (final sample in samples) {
    final repo = sample.repo;
    buffer.writeln('---');
    buffer.writeln('repo: ${repo.fullName}');
    buffer.writeln('watched: ${sample.watched}');
    buffer.writeln('private: ${repo.isPrivate}');
    buffer.writeln('language: ${repo.language ?? 'unknown'}');
    buffer.writeln('topics: ${repo.topics.take(8).join(', ')}');
    buffer.writeln('description: ${repo.description}');
    buffer.writeln('readme_snippet:\n${sample.readme}');
  }
  return buffer.toString();
}

String? _extractJsonObject(String text) {
  final trimmed = text.trim();
  final withoutFence = trimmed
      .replaceFirst(RegExp(r'^```(?:json)?', multiLine: true), '')
      .replaceFirst(RegExp(r'```$', multiLine: true), '')
      .trim();
  final start = withoutFence.indexOf('{');
  final end = withoutFence.lastIndexOf('}');
  if (start == -1 || end == -1 || end <= start) return null;
  return withoutFence.substring(start, end + 1);
}

String _extractProviderText(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) return '';
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
  if (content is List) {
    final parts = <String>[];
    for (final item in content) {
      if (item is Map<String, dynamic>) {
        final text = item['text'];
        if (text is String && text.trim().isNotEmpty) parts.add(text.trim());
      }
    }
    return parts.join('\n');
  }
  return '';
}

List<String> _nonEmptyList(dynamic value) {
  if (value is! List) return const [];
  return value.map((item) => item.toString().trim()).where((item) => item.isNotEmpty).toList();
}

_DigestProviderFlavor _detectFlavor(String baseUrl, String model) {
  final probe = '$baseUrl $model'.toLowerCase();
  if (probe.contains('anthropic') || probe.contains('claude') || probe.contains('mimo-')) {
    return _DigestProviderFlavor.anthropic;
  }
  return _DigestProviderFlavor.openAi;
}

String _normalizedBaseUrl(String baseUrl) {
  return baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
}

String _savedOrDefault(String? value, String fallback) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? fallback : trimmed;
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

String _friendlySocketError(SocketException error) {
  final raw = error.message.trim().isEmpty ? error.toString() : error.message.trim();
  final lower = raw.toLowerCase();
  if (lower.contains('failed host lookup') ||
      lower.contains('no address associated') ||
      lower.contains('temporary failure in name resolution')) {
    return 'Network/DNS issue: the device cannot resolve the provider host.';
  }
  return raw;
}

String _compact(String value, int limit) {
  final trimmed = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (trimmed.length <= limit) return trimmed;
  return '${trimmed.substring(0, limit - 1)}...';
}
