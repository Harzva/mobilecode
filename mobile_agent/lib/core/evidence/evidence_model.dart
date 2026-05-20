// lib/core/evidence/evidence_model.dart
// Unified evidence model for runtime, Git, collaboration, and release QA.
//
// Designed to be consumed by T12 diagnostics UI, T14 approval queue,
// and T14 audit log. All fields are JSON-serializable.

/// Category of the evidence source.
enum EvidenceSource {
  runtimeProvider,
  helperHealth,
  gitRuntime,
  commitPlan,
  secretScan,
  pushPreflight,
  collaborationPreview,
  releaseReadiness,
  approvalQueue,
  auditLog,
}

/// Category of evidence event.
enum EvidenceCategory {
  health,
  status,
  diff,
  filePreview,
  dryRun,
  preflight,
  blocked,
  executed,
  warning,
  error,
  secret,
}

/// Severity of the evidence.
enum EvidenceSeverity {
  info,
  low,
  medium,
  high,
  critical,
}

/// Execution status of the action that produced this evidence.
enum EvidenceStatus {
  readOnly,
  dryRun,
  preflight,
  blocked,
  executed,
  failed,
}

/// Unified evidence record.
///
/// Represents a single piece of evidence from any MobileCode subsystem.
/// Can represent read-only, dry-run, preflight, blocked, or executed results.
/// Does not contain raw secrets.
class Evidence {
  const Evidence({
    required this.id,
    required this.source,
    required this.category,
    required this.severity,
    required this.title,
    required this.summary,
    this.details = const {},
    this.status = EvidenceStatus.readOnly,
    this.dryRun = false,
    this.blockedOperations = const [],
    this.redacted = false,
    required this.createdAt,
    this.relatedActionId,
  });

  final String id;
  final EvidenceSource source;
  final EvidenceCategory category;
  final EvidenceSeverity severity;
  final String title;
  final String summary;
  final Map<String, dynamic> details;
  final EvidenceStatus status;
  final bool dryRun;
  final List<String> blockedOperations;
  final bool redacted;
  final DateTime createdAt;
  final String? relatedActionId;

  Evidence copyWith({
    String? id,
    EvidenceSource? source,
    EvidenceCategory? category,
    EvidenceSeverity? severity,
    String? title,
    String? summary,
    Map<String, dynamic>? details,
    EvidenceStatus? status,
    bool? dryRun,
    List<String>? blockedOperations,
    bool? redacted,
    DateTime? createdAt,
    String? relatedActionId,
  }) {
    return Evidence(
      id: id ?? this.id,
      source: source ?? this.source,
      category: category ?? this.category,
      severity: severity ?? this.severity,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      details: details ?? this.details,
      status: status ?? this.status,
      dryRun: dryRun ?? this.dryRun,
      blockedOperations: blockedOperations ?? this.blockedOperations,
      redacted: redacted ?? this.redacted,
      createdAt: createdAt ?? this.createdAt,
      relatedActionId: relatedActionId ?? this.relatedActionId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'source': source.name,
        'category': category.name,
        'severity': severity.name,
        'title': title,
        'summary': summary,
        'details': details,
        'status': status.name,
        'dryRun': dryRun,
        'blockedOperations': blockedOperations,
        'redacted': redacted,
        'createdAt': createdAt.toIso8601String(),
        if (relatedActionId != null) 'relatedActionId': relatedActionId,
      };

  factory Evidence.fromJson(Map<String, dynamic> json) {
    return Evidence(
      id: json['id'] as String? ?? '',
      source: EvidenceSource.values.firstWhere(
        (e) => e.name == json['source'],
        orElse: () => EvidenceSource.runtimeProvider,
      ),
      category: EvidenceCategory.values.firstWhere(
        (e) => e.name == json['category'],
        orElse: () => EvidenceCategory.status,
      ),
      severity: EvidenceSeverity.values.firstWhere(
        (e) => e.name == json['severity'],
        orElse: () => EvidenceSeverity.info,
      ),
      title: json['title'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      details: (json['details'] as Map<String, dynamic>?) ?? const {},
      status: EvidenceStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => EvidenceStatus.readOnly,
      ),
      dryRun: json['dryRun'] as bool? ?? false,
      blockedOperations: (json['blockedOperations'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      redacted: json['redacted'] as bool? ?? false,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      relatedActionId: json['relatedActionId'] as String?,
    );
  }

  @override
  String toString() => 'Evidence($id, ${source.name}/${category.name}, '
      '${severity.name}, ${status.name})';
}

/// Generate a unique evidence ID.
String generateEvidenceId() {
  return 'ev-${DateTime.now().millisecondsSinceEpoch}'
      '-${_randomHex(6)}';
}

String _randomHex(int length) {
  // Simple hex string from timestamp; not cryptographically random.
  final now = DateTime.now().microsecondsSinceEpoch;
  final hex = now.toRadixString(16);
  return hex.padLeft(length, '0').substring(hex.length - length);
}

// ---------------------------------------------------------------------------
// H02: Action Schema & ActionEvidence
// ---------------------------------------------------------------------------

/// Canonical MobileCode action names.
///
/// Covers the first-class tool actions that the harness can execute.
/// This enum is the single source of truth for action identity.
enum MobileCodeAction {
  writeFile,
  readFile,
  openFile,
  previewHtml,
  publishPages,
  runCommand,
  cloneRepo,
  linkRemoteRepo,
  commitFiles,
  triggerGitHubAction,
  inspectRelease,
  installSkill,
  registerMcp,
  openFolder,
  traceParseInstruction,
  traceSelectTool,
  traceCallProvider,
  traceWriteArtifact,
  traceReportChat,
}

/// Risk level for an action, used for approval gating.
enum ActionRisk {
  safe,
  low,
  medium,
  high,
  critical,
}

/// A serializable description of a planned action.
///
/// Captures *what* the harness intends to do, without storing secrets.
/// Designed for audit logs, approval queues, and trace UI.
class ActionSchema {
  ActionSchema({
    required this.actionName,
    this.paramsSummary = '',
    this.params = const {},
    this.requestId,
    this.risk = ActionRisk.safe,
    this.approvalRequired = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final MobileCodeAction actionName;

  /// Human-readable parameter summary. Must not contain secrets.
  final String paramsSummary;

  /// Optional structured safe parameters. Do not store secrets here.
  final Map<String, dynamic> params;

  /// Optional caller-supplied request id for correlation.
  final String? requestId;

  /// Risk level of this action.
  final ActionRisk risk;

  /// Whether human approval is required before execution.
  final bool approvalRequired;

  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'actionName': actionName.name,
        'paramsSummary': paramsSummary,
        'params': params,
        if (requestId != null) 'requestId': requestId,
        'risk': risk.name,
        'approvalRequired': approvalRequired,
        'createdAt': createdAt.toIso8601String(),
      };

  factory ActionSchema.fromJson(Map<String, dynamic> json) {
    return ActionSchema(
      actionName: MobileCodeAction.values.firstWhere(
        (e) => e.name == json['actionName'],
        orElse: () => MobileCodeAction.runCommand,
      ),
      paramsSummary: json['paramsSummary'] as String? ?? '',
      params: (json['params'] as Map<String, dynamic>?) ?? const {},
      requestId: json['requestId'] as String?,
      risk: ActionRisk.values.firstWhere(
        (e) => e.name == json['risk'],
        orElse: () => ActionRisk.safe,
      ),
      approvalRequired: json['approvalRequired'] as bool? ?? false,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  @override
  String toString() =>
      'ActionSchema(${actionName.name}, risk=${risk.name})';
}

/// Execution evidence for a single MobileCode action.
///
/// Every executed action produces one ActionEvidence record. It captures
/// timing, outcome, artifacts, failure classification, and recovery hints.
/// Does NOT store secrets, tokens, or raw credential data.
class ActionEvidence {
  ActionEvidence({
    required this.evidenceId,
    required this.actionName,
    this.paramsSummary = '',
    required this.startedAt,
    DateTime? endedAt,
    this.success = false,
    this.artifactPaths = const [],
    this.urls = const [],
    this.logs = const [],
    this.exitCode,
    this.failureKind,
    this.recoveryActions = const [],
    Map<String, dynamic>? metadata,
  })  : endedAt = endedAt ?? DateTime.now(),
        metadata = metadata ?? {};

  /// Unique identifier for this evidence record.
  final String evidenceId;

  /// Which action was executed.
  final MobileCodeAction actionName;

  /// Human-readable summary of the parameters used (no secrets).
  final String paramsSummary;

  /// When the action started executing.
  final DateTime startedAt;

  /// When the action finished (success or failure).
  final DateTime endedAt;

  /// Whether the action completed successfully.
  final bool success;

  /// File paths produced or modified by the action.
  final List<String> artifactPaths;

  /// URLs produced or opened by the action.
  final List<String> urls;

  /// Log lines captured during execution.
  final List<String> logs;

  /// Process exit code, if applicable.
  final int? exitCode;

  /// Stable failure category string.
  ///
  /// Uses stable string values rather than importing RuntimeTaskFailureKind
  /// to avoid a core->services import cycle. Expected values mirror
  /// RuntimeTaskFailureKind names: timeout, cancelled, dependencyMissing,
  /// commandBlocked, cwdOutsideWorkspace, authFailed, processFailed,
  /// runtimeLost, unknown.
  final String? failureKind;

  /// Suggested recovery actions for the user.
  final List<String> recoveryActions;

  /// Arbitrary non-secret metadata for extensibility.
  final Map<String, dynamic> metadata;

  /// Computed duration in milliseconds.
  int get durationMs => endedAt.difference(startedAt).inMilliseconds;

  // ---------------------------------------------------------------------------
  // Factory helpers
  // ---------------------------------------------------------------------------

  /// Create evidence for an action that just started.
  factory ActionEvidence.started({
    required MobileCodeAction actionName,
    String paramsSummary = '',
    String? evidenceId,
  }) {
    return ActionEvidence(
      evidenceId: evidenceId ?? generateEvidenceId(),
      actionName: actionName,
      paramsSummary: paramsSummary,
      startedAt: DateTime.now(),
      endedAt: DateTime.now(),
      success: false,
    );
  }

  /// Create evidence for a successfully completed action.
  factory ActionEvidence.succeeded({
    required MobileCodeAction actionName,
    required DateTime startedAt,
    String paramsSummary = '',
    String? evidenceId,
    List<String> artifactPaths = const [],
    List<String> urls = const [],
    List<String> logs = const [],
    int? exitCode,
  }) {
    return ActionEvidence(
      evidenceId: evidenceId ?? generateEvidenceId(),
      actionName: actionName,
      paramsSummary: paramsSummary,
      startedAt: startedAt,
      endedAt: DateTime.now(),
      success: true,
      artifactPaths: artifactPaths,
      urls: urls,
      logs: logs,
      exitCode: exitCode,
    );
  }

  /// Create evidence for a failed action.
  factory ActionEvidence.failed({
    required MobileCodeAction actionName,
    required DateTime startedAt,
    String paramsSummary = '',
    String? evidenceId,
    String? failureKind,
    List<String> recoveryActions = const [],
    List<String> logs = const [],
    int? exitCode,
  }) {
    return ActionEvidence(
      evidenceId: evidenceId ?? generateEvidenceId(),
      actionName: actionName,
      paramsSummary: paramsSummary,
      startedAt: startedAt,
      endedAt: DateTime.now(),
      success: false,
      failureKind: failureKind,
      recoveryActions: recoveryActions,
      logs: logs,
      exitCode: exitCode,
    );
  }

  // ---------------------------------------------------------------------------
  // Conversion to existing Evidence model
  // ---------------------------------------------------------------------------

  /// Convert this ActionEvidence into the unified [Evidence] model.
  ///
  /// Embeds the full ActionEvidence JSON under [Evidence.details] so that
  /// downstream consumers (diagnostics UI, audit log) can access all fields.
  Evidence toEvidence() {
    return Evidence(
      id: evidenceId,
      source: EvidenceSource.runtimeProvider,
      category: success ? EvidenceCategory.executed : EvidenceCategory.error,
      severity: success
          ? EvidenceSeverity.info
          : (failureKind == 'timeout' || failureKind == 'runtimeLost'
              ? EvidenceSeverity.high
              : EvidenceSeverity.medium),
      title: '${actionName.name} ${success ? "succeeded" : "failed"}',
      summary: paramsSummary.isNotEmpty
          ? paramsSummary
          : actionName.name,
      details: toJson(),
      status: success ? EvidenceStatus.executed : EvidenceStatus.failed,
      createdAt: startedAt,
      relatedActionId: evidenceId,
    );
  }

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
        'evidenceId': evidenceId,
        'actionName': actionName.name,
        'paramsSummary': paramsSummary,
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt.toIso8601String(),
        'durationMs': durationMs,
        'success': success,
        'artifactPaths': artifactPaths,
        'urls': urls,
        'logs': logs,
        if (exitCode != null) 'exitCode': exitCode,
        if (failureKind != null) 'failureKind': failureKind,
        'recoveryActions': recoveryActions,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  factory ActionEvidence.fromJson(Map<String, dynamic> json) {
    return ActionEvidence(
      evidenceId: json['evidenceId'] as String? ?? '',
      actionName: MobileCodeAction.values.firstWhere(
        (e) => e.name == json['actionName'],
        orElse: () => MobileCodeAction.runCommand,
      ),
      paramsSummary: json['paramsSummary'] as String? ?? '',
      startedAt: json['startedAt'] != null
          ? DateTime.tryParse(json['startedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      endedAt: json['endedAt'] != null
          ? DateTime.tryParse(json['endedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      success: json['success'] as bool? ?? false,
      artifactPaths: (json['artifactPaths'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      urls: (json['urls'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      logs: (json['logs'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      exitCode: json['exitCode'] as int?,
      failureKind: json['failureKind'] as String?,
      recoveryActions: (json['recoveryActions'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
    );
  }

  @override
  String toString() =>
      'ActionEvidence(${actionName.name}, success=$success, '
      'duration=${durationMs}ms${failureKind != null ? ", fail=$failureKind" : ""})';
}

/// Default failure kinds matching RuntimeTaskFailureKind stable values.
///
/// Provided as a convenience for callers that want compile-time constants
/// rather than free-form strings.
class ActionFailureKind {
  static const String timeout = 'timeout';
  static const String cancelled = 'cancelled';
  static const String dependencyMissing = 'dependencyMissing';
  static const String commandBlocked = 'commandBlocked';
  static const String cwdOutsideWorkspace = 'cwdOutsideWorkspace';
  static const String authFailed = 'authFailed';
  static const String processFailed = 'processFailed';
  static const String runtimeLost = 'runtimeLost';
  static const String unknown = 'unknown';
}
