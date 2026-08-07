/// Models for Mobile Harness Reasoning Strategy P1/P2.
///
/// These contracts intentionally do not write to [MemoryService], do not call
/// providers, and do not represent counted benchmark results. They mirror the
/// strategy-ablation document contract while keeping Dart field names idiomatic.
library;

import 'dart:math' as math;

class HarnessSourceLimits {
  const HarnessSourceLimits({
    this.recentTurns = 12,
    this.maxChars = 12000,
    this.maxErrorPatterns = 5,
  });

  final int recentTurns;
  final int maxChars;
  final int maxErrorPatterns;

  Map<String, dynamic> toJson() => {
        'recent_turns': recentTurns,
        'max_chars': maxChars,
        'max_error_patterns': maxErrorPatterns,
      };

  factory HarnessSourceLimits.fromJson(Map<String, dynamic> json) {
    return HarnessSourceLimits(
      recentTurns: _readInt(json, const ['recent_turns', 'recentTurns'], 12),
      maxChars: _readInt(json, const ['max_chars', 'maxChars'], 12000),
      maxErrorPatterns:
          _readInt(json, const ['max_error_patterns', 'maxErrorPatterns'], 5),
    );
  }
}

class HarnessRecentTurn {
  const HarnessRecentTurn({
    required this.role,
    required this.summary,
    this.evidenceIds = const [],
  });

  final String role;
  final String summary;
  final List<String> evidenceIds;

  HarnessRecentTurn copyWith({
    String? role,
    String? summary,
    List<String>? evidenceIds,
  }) {
    return HarnessRecentTurn(
      role: role ?? this.role,
      summary: summary ?? this.summary,
      evidenceIds: evidenceIds ?? this.evidenceIds,
    );
  }

  Map<String, dynamic> toJson() => {
        'role': role,
        'summary': summary,
        'evidence_ids': evidenceIds,
      };

  factory HarnessRecentTurn.fromJson(Map<String, dynamic> json) {
    return HarnessRecentTurn(
      role: _readString(json, const ['role']),
      summary: _readString(json, const ['summary']),
      evidenceIds: _readStringList(_readValue(json, const ['evidence_ids', 'evidenceIds'])),
    );
  }
}

class HarnessRedaction {
  const HarnessRedaction({
    required this.applied,
    this.classes = const [],
  });

  final bool applied;
  final List<String> classes;

  Map<String, dynamic> toJson() => {
        'applied': applied,
        'classes': classes,
      };

  factory HarnessRedaction.fromJson(Map<String, dynamic> json) {
    return HarnessRedaction(
      applied: _readBool(json, const ['applied'], false),
      classes: _readStringList(json['classes']),
    );
  }
}

class HarnessMemoryPacket {
  const HarnessMemoryPacket({
    required this.packetId,
    required this.schemaVersion,
    required this.sessionId,
    required this.runId,
    required this.createdAt,
    required this.ttlSeconds,
    required this.sourceLimits,
    required this.userGoal,
    required this.conversationSummary,
    this.recentTurns = const [],
    this.projectFacts = const [],
    this.userPreferences = const [],
    this.errorPatterns = const [],
    this.activeConstraints = const [],
    this.redaction = const HarnessRedaction(applied: false),
  });

  final String packetId;
  final String schemaVersion;
  final String sessionId;
  final String runId;
  final DateTime createdAt;
  final int ttlSeconds;
  final HarnessSourceLimits sourceLimits;
  final String userGoal;
  final String conversationSummary;
  final List<HarnessRecentTurn> recentTurns;
  final List<Map<String, dynamic>> projectFacts;
  final List<Map<String, dynamic>> userPreferences;
  final List<Map<String, dynamic>> errorPatterns;
  final List<String> activeConstraints;
  final HarnessRedaction redaction;

  bool isExpired(DateTime now) {
    return !now.isBefore(createdAt.add(Duration(seconds: ttlSeconds)));
  }

  HarnessMemoryPacket compacted({
    int? maxChars,
    int? recentTurnsLimit,
    int? maxErrorPatterns,
  }) {
    final limit = math.max(0, maxChars ?? sourceLimits.maxChars);
    final turnLimit = math.max(0, recentTurnsLimit ?? sourceLimits.recentTurns);
    final errorLimit = math.max(0, maxErrorPatterns ?? sourceLimits.maxErrorPatterns);
    final budget = _TextBudget(limit);

    final compactTurns = recentTurns
        .skip(math.max(0, recentTurns.length - turnLimit))
        .map(
          (turn) => turn.copyWith(
            summary: budget.take(turn.summary),
            evidenceIds: List<String>.unmodifiable(turn.evidenceIds),
          ),
        )
        .toList(growable: false);

    return HarnessMemoryPacket(
      packetId: packetId,
      schemaVersion: schemaVersion,
      sessionId: sessionId,
      runId: runId,
      createdAt: createdAt,
      ttlSeconds: ttlSeconds,
      sourceLimits: HarnessSourceLimits(
        recentTurns: turnLimit,
        maxChars: limit,
        maxErrorPatterns: errorLimit,
      ),
      userGoal: budget.take(userGoal),
      conversationSummary: budget.take(conversationSummary),
      recentTurns: compactTurns,
      projectFacts: _compactMapList(projectFacts, budget),
      userPreferences: _compactMapList(userPreferences, budget),
      errorPatterns: _compactMapList(
        errorPatterns.take(errorLimit).toList(growable: false),
        budget,
      ),
      activeConstraints: activeConstraints.map(budget.take).toList(growable: false),
      redaction: redaction,
    );
  }

  Map<String, dynamic> toJson() => {
        'packet_id': packetId,
        'schema_version': schemaVersion,
        'session_id': sessionId,
        'run_id': runId,
        'created_at': createdAt.toIso8601String(),
        'ttl_seconds': ttlSeconds,
        'source_limits': sourceLimits.toJson(),
        'user_goal': userGoal,
        'conversation_summary': conversationSummary,
        'recent_turns': recentTurns.map((turn) => turn.toJson()).toList(),
        'project_facts': projectFacts,
        'user_preferences': userPreferences,
        'error_patterns': errorPatterns,
        'active_constraints': activeConstraints,
        'redaction': redaction.toJson(),
      };

  factory HarnessMemoryPacket.fromJson(Map<String, dynamic> json) {
    return HarnessMemoryPacket(
      packetId: _readString(json, const ['packet_id', 'packetId']),
      schemaVersion: _readString(json, const ['schema_version', 'schemaVersion'], '0.1.0'),
      sessionId: _readString(json, const ['session_id', 'sessionId']),
      runId: _readString(json, const ['run_id', 'runId']),
      createdAt: _readDateTime(json, const ['created_at', 'createdAt']),
      ttlSeconds: _readInt(json, const ['ttl_seconds', 'ttlSeconds'], 86400),
      sourceLimits: HarnessSourceLimits.fromJson(
        _readMap(_readValue(json, const ['source_limits', 'sourceLimits'])),
      ),
      userGoal: _readString(json, const ['user_goal', 'userGoal']),
      conversationSummary: _readString(
        json,
        const ['conversation_summary', 'conversationSummary'],
      ),
      recentTurns: _readMapList(_readValue(json, const ['recent_turns', 'recentTurns']))
          .map(HarnessRecentTurn.fromJson)
          .toList(growable: false),
      projectFacts: _readMapList(_readValue(json, const ['project_facts', 'projectFacts'])),
      userPreferences: _readMapList(_readValue(json, const ['user_preferences', 'userPreferences'])),
      errorPatterns: _readMapList(_readValue(json, const ['error_patterns', 'errorPatterns'])),
      activeConstraints: _readStringList(_readValue(json, const ['active_constraints', 'activeConstraints'])),
      redaction: HarnessRedaction.fromJson(
        _readMap(_readValue(json, const ['redaction'])),
      ),
    );
  }
}

enum HandoffInputFilter {
  summaryOnly,
  removeToolCalls,
  evidenceRefsOnly,
}

extension HandoffInputFilterWire on HandoffInputFilter {
  String get wire => switch (this) {
        HandoffInputFilter.summaryOnly => 'summary_only',
        HandoffInputFilter.removeToolCalls => 'remove_tool_calls',
        HandoffInputFilter.evidenceRefsOnly => 'evidence_refs_only',
      };
}

class HandoffBudget {
  const HandoffBudget({
    this.maxRounds = 3,
    this.maxTokens = 4000,
    this.timeoutMs = 120000,
  });

  final int maxRounds;
  final int maxTokens;
  final int timeoutMs;

  Map<String, dynamic> toJson() => {
        'max_rounds': maxRounds,
        'max_tokens': maxTokens,
        'timeout_ms': timeoutMs,
      };

  factory HandoffBudget.fromJson(Map<String, dynamic> json) {
    return HandoffBudget(
      maxRounds: _readInt(json, const ['max_rounds', 'maxRounds'], 3),
      maxTokens: _readInt(json, const ['max_tokens', 'maxTokens'], 4000),
      timeoutMs: _readInt(json, const ['timeout_ms', 'timeoutMs'], 120000),
    );
  }
}

class HandoffReturnContract {
  const HandoffReturnContract({
    this.mustReturn = const ['status', 'summary', 'evidence_ids', 'blockers'],
    this.noRawSecretEcho = true,
  });

  final List<String> mustReturn;
  final bool noRawSecretEcho;

  Map<String, dynamic> toJson() => {
        'must_return': mustReturn,
        'no_raw_secret_echo': noRawSecretEcho,
      };

  factory HandoffReturnContract.fromJson(Map<String, dynamic> json) {
    return HandoffReturnContract(
      mustReturn: _readStringList(_readValue(json, const ['must_return', 'mustReturn'])),
      noRawSecretEcho:
          _readBool(json, const ['no_raw_secret_echo', 'noRawSecretEcho'], true),
    );
  }
}

class HandoffPacket {
  const HandoffPacket({
    required this.handoffId,
    required this.fromRole,
    required this.toRole,
    required this.reason,
    required this.priority,
    required this.stepId,
    required this.task,
    required this.inputFilter,
    this.allowedTools = const [],
    this.forbiddenTools = const [],
    this.context = const {},
    this.budget = const HandoffBudget(),
    this.returnContract = const HandoffReturnContract(),
  });

  final String handoffId;
  final String fromRole;
  final String toRole;
  final String reason;
  final String priority;
  final String stepId;
  final String task;
  final HandoffInputFilter inputFilter;
  final List<String> allowedTools;
  final List<String> forbiddenTools;
  final Map<String, dynamic> context;
  final HandoffBudget budget;
  final HandoffReturnContract returnContract;

  Map<String, dynamic> filteredContextForRole(String role) {
    final withoutRaw = _sanitizeHandoffContext(context);
    final roleSpecific = _readMap(withoutRaw['role_context']).isNotEmpty
        ? _readMap(_readMap(withoutRaw['role_context'])[role])
        : const <String, dynamic>{};
    final merged = <String, dynamic>{
      ...withoutRaw,
      if (roleSpecific.isNotEmpty) ...roleSpecific,
    }..remove('role_context');

    return switch (inputFilter) {
      HandoffInputFilter.summaryOnly => _summaryOnlyContext(merged),
      HandoffInputFilter.removeToolCalls => _removeToolCallsContext(merged),
      HandoffInputFilter.evidenceRefsOnly => _evidenceRefsOnlyContext(merged),
    };
  }

  Map<String, dynamic> toJson() => {
        'handoff_id': handoffId,
        'from_role': fromRole,
        'to_role': toRole,
        'reason': reason,
        'priority': priority,
        'step_id': stepId,
        'task': task,
        'input_filter': inputFilter.wire,
        'allowed_tools': allowedTools,
        'forbidden_tools': forbiddenTools,
        'context': filteredContextForRole(toRole),
        'budget': budget.toJson(),
        'return_contract': returnContract.toJson(),
      };

  factory HandoffPacket.fromJson(Map<String, dynamic> json) {
    return HandoffPacket(
      handoffId: _readString(json, const ['handoff_id', 'handoffId']),
      fromRole: _readString(json, const ['from_role', 'fromRole']),
      toRole: _readString(json, const ['to_role', 'toRole']),
      reason: _readString(json, const ['reason']),
      priority: _readString(json, const ['priority'], 'normal'),
      stepId: _readString(json, const ['step_id', 'stepId']),
      task: _readString(json, const ['task']),
      inputFilter: _handoffInputFilterFromWire(
        _readString(json, const ['input_filter', 'inputFilter'], 'summary_only'),
      ),
      allowedTools: _readStringList(_readValue(json, const ['allowed_tools', 'allowedTools'])),
      forbiddenTools: _readStringList(_readValue(json, const ['forbidden_tools', 'forbiddenTools'])),
      context: _readMap(_readValue(json, const ['context'])),
      budget: HandoffBudget.fromJson(_readMap(_readValue(json, const ['budget']))),
      returnContract: HandoffReturnContract.fromJson(
        _readMap(_readValue(json, const ['return_contract', 'returnContract'])),
      ),
    );
  }
}

enum StrategyTraceStatus {
  scaffoldNotRun,
  dryRunNotCounted,
  running,
  passed,
  blocked,
  failed,
}

extension StrategyTraceStatusWire on StrategyTraceStatus {
  String get wire => switch (this) {
        StrategyTraceStatus.scaffoldNotRun => 'scaffold_not_run',
        StrategyTraceStatus.dryRunNotCounted => 'dry_run_not_counted',
        StrategyTraceStatus.running => 'running',
        StrategyTraceStatus.passed => 'passed',
        StrategyTraceStatus.blocked => 'blocked',
        StrategyTraceStatus.failed => 'failed',
      };
}

enum StrategyEventType {
  plan,
  think,
  act,
  observe,
  verify,
  report,
  handoff,
  scaffold,
  replan,
  memoryCommit,
}

extension StrategyEventTypeWire on StrategyEventType {
  String get wire => switch (this) {
        StrategyEventType.plan => 'plan',
        StrategyEventType.think => 'think',
        StrategyEventType.act => 'act',
        StrategyEventType.observe => 'observe',
        StrategyEventType.verify => 'verify',
        StrategyEventType.report => 'report',
        StrategyEventType.handoff => 'handoff',
        StrategyEventType.scaffold => 'scaffold',
        StrategyEventType.replan => 'replan',
        StrategyEventType.memoryCommit => 'memory_commit',
      };
}

class StrategyTraceEvent {
  const StrategyTraceEvent({
    required this.eventId,
    required this.type,
    required this.role,
    this.stepId,
    required this.startedAt,
    this.endedAt,
    this.toolName,
    this.evidenceId,
    required this.summary,
    this.countsAsExperiment = false,
    this.metadata = const {},
  });

  final String eventId;
  final StrategyEventType type;
  final String role;
  final String? stepId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? toolName;
  final String? evidenceId;
  final String summary;
  final bool countsAsExperiment;
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() => {
        'event_id': eventId,
        'type': type.wire,
        'role': role,
        if (stepId != null) 'step_id': stepId,
        'started_at': startedAt.toIso8601String(),
        if (endedAt != null) 'ended_at': endedAt!.toIso8601String(),
        if (toolName != null) 'tool_name': toolName,
        if (evidenceId != null) 'evidence_id': evidenceId,
        'summary': summary,
        'counts_as_experiment': countsAsExperiment,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory StrategyTraceEvent.fromJson(Map<String, dynamic> json) {
    return StrategyTraceEvent(
      eventId: _readString(json, const ['event_id', 'eventId']),
      type: _strategyEventTypeFromWire(_readString(json, const ['type'], 'scaffold')),
      role: _readString(json, const ['role']),
      stepId: _readNullableString(json, const ['step_id', 'stepId']),
      startedAt: _readDateTime(json, const ['started_at', 'startedAt']),
      endedAt: _readNullableDateTime(json, const ['ended_at', 'endedAt']),
      toolName: _readNullableString(json, const ['tool_name', 'toolName']),
      evidenceId: _readNullableString(json, const ['evidence_id', 'evidenceId']),
      summary: _readString(json, const ['summary']),
      countsAsExperiment:
          _readBool(json, const ['counts_as_experiment', 'countsAsExperiment'], false),
      metadata: _readMap(_readValue(json, const ['metadata'])),
    );
  }
}

class StrategyTrace {
  StrategyTrace({
    required this.traceId,
    required this.strategyId,
    required this.traceStatus,
    List<StrategyTraceEvent>? events,
    this.handoffCount = 0,
    this.planningRevisions = 0,
    this.verificationFailuresRecovered = 0,
    this.failureKind,
  }) : events = events ?? <StrategyTraceEvent>[];

  final String traceId;
  final String strategyId;
  StrategyTraceStatus traceStatus;
  final List<StrategyTraceEvent> events;
  int handoffCount;
  int planningRevisions;
  int verificationFailuresRecovered;
  String? failureKind;

  void appendEvent(StrategyTraceEvent event) {
    events.add(event);
    if (event.type == StrategyEventType.handoff) {
      handoffCount += 1;
    }
    if (event.type == StrategyEventType.replan) {
      planningRevisions += 1;
    }
  }

  Map<String, dynamic> toJson() => {
        'trace_id': traceId,
        'strategy_id': strategyId,
        'trace_status': traceStatus.wire,
        'events': events.map((event) => event.toJson()).toList(),
        'handoff_count': handoffCount,
        'planning_revisions': planningRevisions,
        'verification_failures_recovered': verificationFailuresRecovered,
        'failure_kind': failureKind,
        'counts_as_experiment': false,
      };

  Map<String, dynamic> toBenchmarkJson() => toJson();

  factory StrategyTrace.fromJson(Map<String, dynamic> json) {
    return StrategyTrace(
      traceId: _readString(json, const ['trace_id', 'traceId']),
      strategyId: _readString(json, const ['strategy_id', 'strategyId']),
      traceStatus: _strategyTraceStatusFromWire(
        _readString(json, const ['trace_status', 'traceStatus'], 'scaffold_not_run'),
      ),
      events: _readMapList(_readValue(json, const ['events']))
          .map(StrategyTraceEvent.fromJson)
          .toList(growable: true),
      handoffCount: _readInt(json, const ['handoff_count', 'handoffCount'], 0),
      planningRevisions:
          _readInt(json, const ['planning_revisions', 'planningRevisions'], 0),
      verificationFailuresRecovered: _readInt(
        json,
        const ['verification_failures_recovered', 'verificationFailuresRecovered'],
        0,
      ),
      failureKind: _readNullableString(json, const ['failure_kind', 'failureKind']),
    );
  }
}

enum StepVerificationStatus {
  pass,
  fail,
  blocked,
  failAccepted,
  notRun,
}

extension StepVerificationStatusWire on StepVerificationStatus {
  String get wire => switch (this) {
        StepVerificationStatus.pass => 'pass',
        StepVerificationStatus.fail => 'fail',
        StepVerificationStatus.blocked => 'blocked',
        StepVerificationStatus.failAccepted => 'fail_accepted',
        StepVerificationStatus.notRun => 'not_run',
      };
}

class StepVerificationCheck {
  const StepVerificationCheck({
    required this.name,
    required this.status,
    this.evidenceId,
  });

  final String name;
  final StepVerificationStatus status;
  final String? evidenceId;

  Map<String, dynamic> toJson() => {
        'name': name,
        'status': status.wire,
        if (evidenceId != null) 'evidence_id': evidenceId,
      };

  factory StepVerificationCheck.fromJson(Map<String, dynamic> json) {
    return StepVerificationCheck(
      name: _readString(json, const ['name']),
      status: _stepVerificationStatusFromWire(
        _readString(json, const ['status'], 'not_run'),
      ),
      evidenceId: _readNullableString(json, const ['evidence_id', 'evidenceId']),
    );
  }
}

class StepVerification {
  const StepVerification({
    required this.stepId,
    this.verifierId = 'mobilecode_step_verifier_v1',
    required this.status,
    required this.confidence,
    this.checks = const [],
    this.issues = const [],
    this.critique = '',
    this.retryAllowed = false,
    this.retryCount = 0,
    this.evidenceIds = const [],
    this.countsAsVerifiedSuccess = false,
  });

  final String stepId;
  final String verifierId;
  final StepVerificationStatus status;
  final double confidence;
  final List<StepVerificationCheck> checks;
  final List<String> issues;
  final String critique;
  final bool retryAllowed;
  final int retryCount;
  final List<String> evidenceIds;
  final bool countsAsVerifiedSuccess;

  bool get shouldRetry =>
      status == StepVerificationStatus.fail && retryAllowed && retryCount == 0;

  Map<String, dynamic> toJson() => {
        'step_id': stepId,
        'verifier_id': verifierId,
        'status': status.wire,
        'confidence': confidence,
        'checks': checks.map((check) => check.toJson()).toList(),
        'issues': issues,
        'critique': critique,
        'retry_allowed': retryAllowed,
        'retry_count': retryCount,
        'evidence_ids': evidenceIds,
        'counts_as_verified_success': countsAsVerifiedSuccess,
      };

  factory StepVerification.fromJson(Map<String, dynamic> json) {
    return StepVerification(
      stepId: _readString(json, const ['step_id', 'stepId']),
      verifierId: _readString(
        json,
        const ['verifier_id', 'verifierId'],
        'mobilecode_step_verifier_v1',
      ),
      status: _stepVerificationStatusFromWire(
        _readString(json, const ['status'], 'not_run'),
      ),
      confidence: _readDouble(json, const ['confidence'], 0),
      checks: _readMapList(_readValue(json, const ['checks']))
          .map(StepVerificationCheck.fromJson)
          .toList(growable: false),
      issues: _readStringList(_readValue(json, const ['issues'])),
      critique: _readString(json, const ['critique']),
      retryAllowed: _readBool(json, const ['retry_allowed', 'retryAllowed'], false),
      retryCount: _readInt(json, const ['retry_count', 'retryCount'], 0),
      evidenceIds: _readStringList(_readValue(json, const ['evidence_ids', 'evidenceIds'])),
      countsAsVerifiedSuccess: _readBool(
        json,
        const ['counts_as_verified_success', 'countsAsVerifiedSuccess'],
        false,
      ),
    );
  }
}

Object? _readValue(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    if (json.containsKey(key)) {
      return json[key];
    }
  }
  return null;
}

String _readString(
  Map<String, dynamic> json,
  List<String> keys, [
  String fallback = '',
]) {
  return _readValue(json, keys)?.toString() ?? fallback;
}

String? _readNullableString(Map<String, dynamic> json, List<String> keys) {
  final value = _readValue(json, keys);
  return value == null ? null : value.toString();
}

int _readInt(Map<String, dynamic> json, List<String> keys, int fallback) {
  final value = _readValue(json, keys);
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

double _readDouble(Map<String, dynamic> json, List<String> keys, double fallback) {
  final value = _readValue(json, keys);
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

bool _readBool(Map<String, dynamic> json, List<String> keys, bool fallback) {
  final value = _readValue(json, keys);
  if (value is bool) {
    return value;
  }
  if (value is String) {
    return value.toLowerCase() == 'true';
  }
  return fallback;
}

DateTime _readDateTime(Map<String, dynamic> json, List<String> keys) {
  return _readNullableDateTime(json, keys) ?? DateTime.fromMillisecondsSinceEpoch(0);
}

DateTime? _readNullableDateTime(Map<String, dynamic> json, List<String> keys) {
  final value = _readValue(json, keys);
  if (value == null) {
    return null;
  }
  if (value is DateTime) {
    return value;
  }
  return DateTime.tryParse(value.toString());
}

Map<String, dynamic> _readMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, dynamic value) => MapEntry(key.toString(), value));
  }
  return const <String, dynamic>{};
}

List<Map<String, dynamic>> _readMapList(Object? value) {
  if (value is! List) {
    return const <Map<String, dynamic>>[];
  }
  return value.map(_readMap).toList(growable: false);
}

List<String> _readStringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return value.map((item) => item.toString()).toList(growable: false);
}

class _TextBudget {
  _TextBudget(this.remaining);

  int remaining;

  String take(String value) {
    if (remaining <= 0) {
      return '';
    }
    if (value.length <= remaining) {
      remaining -= value.length;
      return value;
    }
    final cut = math.max(0, remaining);
    remaining = 0;
    return value.substring(0, cut);
  }
}

List<Map<String, dynamic>> _compactMapList(
  List<Map<String, dynamic>> values,
  _TextBudget budget,
) {
  return values.map((item) => _compactMap(item, budget)).toList(growable: false);
}

Map<String, dynamic> _compactMap(Map<String, dynamic> item, _TextBudget budget) {
  return item.map((key, dynamic value) {
    if (value is String) {
      return MapEntry(key, budget.take(value));
    }
    if (value is List) {
      return MapEntry(key, value.map((entry) => entry is String ? budget.take(entry) : entry).toList());
    }
    return MapEntry(key, value);
  });
}

Map<String, dynamic> _sanitizeHandoffContext(Map<String, dynamic> context) {
  final sanitized = <String, dynamic>{};
  for (final entry in context.entries) {
    final key = entry.key;
    if (_isRawTranscriptKey(key)) {
      continue;
    }
    sanitized[key] = entry.value;
  }
  return sanitized;
}

bool _isRawTranscriptKey(String key) {
  final normalized = key.toLowerCase();
  return normalized == 'rawtranscript' ||
      normalized == 'raw_transcript' ||
      normalized == 'transcript' ||
      normalized == 'messages' ||
      normalized == 'raw_messages';
}

Map<String, dynamic> _summaryOnlyContext(Map<String, dynamic> context) {
  return <String, dynamic>{
    if (context['goal_summary'] != null) 'goal_summary': context['goal_summary'],
    if (context['summary'] != null) 'summary': context['summary'],
    if (context['dependency_results'] != null) 'dependency_results': context['dependency_results'],
    if (context['evidence_ids'] != null) 'evidence_ids': context['evidence_ids'],
    if (context['artifact_paths'] != null) 'artifact_paths': context['artifact_paths'],
  };
}

Map<String, dynamic> _removeToolCallsContext(Map<String, dynamic> context) {
  final sanitized = <String, dynamic>{};
  for (final entry in context.entries) {
    final key = entry.key.toLowerCase();
    if (key == 'toolcalls' || key == 'tool_calls' || key == 'raw_tool_calls') {
      continue;
    }
    sanitized[entry.key] = entry.value;
  }
  return sanitized;
}

Map<String, dynamic> _evidenceRefsOnlyContext(Map<String, dynamic> context) {
  return <String, dynamic>{
    if (context['goal_summary'] != null) 'goal_summary': context['goal_summary'],
    if (context['evidence_ids'] != null) 'evidence_ids': context['evidence_ids'],
    if (context['artifact_paths'] != null) 'artifact_paths': context['artifact_paths'],
    if (context['blockers'] != null) 'blockers': context['blockers'],
  };
}

HandoffInputFilter _handoffInputFilterFromWire(String value) {
  return switch (value) {
    'summary_only' || 'summaryOnly' => HandoffInputFilter.summaryOnly,
    'remove_tool_calls' || 'removeToolCalls' => HandoffInputFilter.removeToolCalls,
    'evidence_refs_only' || 'evidenceRefsOnly' => HandoffInputFilter.evidenceRefsOnly,
    _ => HandoffInputFilter.summaryOnly,
  };
}

StrategyTraceStatus _strategyTraceStatusFromWire(String value) {
  return switch (value) {
    'scaffold_not_run' || 'scaffoldNotRun' => StrategyTraceStatus.scaffoldNotRun,
    'dry_run_not_counted' || 'dryRunNotCounted' => StrategyTraceStatus.dryRunNotCounted,
    'running' => StrategyTraceStatus.running,
    'passed' => StrategyTraceStatus.passed,
    'blocked' => StrategyTraceStatus.blocked,
    'failed' => StrategyTraceStatus.failed,
    _ => StrategyTraceStatus.scaffoldNotRun,
  };
}

StrategyEventType _strategyEventTypeFromWire(String value) {
  return switch (value) {
    'plan' => StrategyEventType.plan,
    'think' => StrategyEventType.think,
    'act' => StrategyEventType.act,
    'observe' => StrategyEventType.observe,
    'verify' => StrategyEventType.verify,
    'report' => StrategyEventType.report,
    'handoff' => StrategyEventType.handoff,
    'scaffold' => StrategyEventType.scaffold,
    'replan' => StrategyEventType.replan,
    'memory_commit' || 'memoryCommit' => StrategyEventType.memoryCommit,
    _ => StrategyEventType.scaffold,
  };
}

StepVerificationStatus _stepVerificationStatusFromWire(String value) {
  return switch (value) {
    'pass' => StepVerificationStatus.pass,
    'fail' => StepVerificationStatus.fail,
    'blocked' => StepVerificationStatus.blocked,
    'fail_accepted' || 'failAccepted' => StepVerificationStatus.failAccepted,
    'not_run' || 'notRun' => StepVerificationStatus.notRun,
    _ => StepVerificationStatus.notRun,
  };
}
