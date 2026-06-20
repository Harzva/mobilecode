/// Harness memory packet bridge for MobileCode reasoning strategies.
///
/// The service reads durable MemoryService data and creates a scoped,
/// redacted, TTL-bound HarnessMemoryPacket. It does not persist memory commits
/// unless a later caller explicitly routes proposals through MemoryService.
library;

export 'reasoning_strategy_models.dart'
    show
        HarnessMemoryPacket,
        HarnessRecentTurn,
        HarnessRedaction,
        HarnessSourceLimits;

import 'memory_service.dart';
import 'reasoning_strategy_models.dart';

class HarnessMemoryPacketService {
  const HarnessMemoryPacketService({
    required MemoryService memoryService,
  }) : _memoryService = memoryService;

  final MemoryService _memoryService;

  Future<HarnessMemoryPacket> buildPacket({
    required String userGoal,
    required String sessionId,
    required String runId,
    DateTime? now,
    int ttlSeconds = 86400,
    HarnessSourceLimits sourceLimits = const HarnessSourceLimits(),
    List<String> activeConstraints = const [
      'no raw transcript in handoff packets',
      'non-counted unless full evidence gate passes',
    ],
  }) async {
    final createdAt = now ?? DateTime.now().toUtc();
    final conversations = await _memoryService.getConversationHistory(
      limit: sourceLimits.recentTurns,
    );
    final projects = await _memoryService.getProjectMemories();
    final errors = await _memoryService.getErrorPatterns();
    final prefs = await _memoryService.getCodePreferences();

    final packet = HarnessMemoryPacket(
      packetId: 'hmp_${runId}_${createdAt.millisecondsSinceEpoch}',
      schemaVersion: '0.1.0',
      sessionId: sessionId,
      runId: runId,
      createdAt: createdAt,
      ttlSeconds: ttlSeconds,
      sourceLimits: sourceLimits,
      userGoal: _redact(userGoal),
      conversationSummary: _conversationSummary(conversations),
      recentTurns: conversations
          .map(
            (record) => HarnessRecentTurn(
              role: 'user_assistant',
              summary: _redact('${record.userMessage}\n${record.aiResponse}'),
              evidenceIds: record.tags,
            ),
          )
          .toList(growable: false),
      projectFacts: projects
          .map(
            (project) => {
              'project_id': project.projectId,
              'project_name': _redact(project.projectName),
              'indexed_files': project.indexedFiles,
              'indexed_functions': project.indexedFunctions,
              'indexed_classes': project.indexedClasses,
              'confidence': 0.8,
            },
          )
          .toList(growable: false),
      userPreferences: [
        {
          'naming_convention': prefs.namingConvention.label,
          'indent_style': prefs.indentStyle.name,
          'indent_size': prefs.indentSize,
          'prefer_const': prefs.preferConst,
          'prefer_final': prefs.preferFinal,
        }
      ],
      errorPatterns: errors
          .take(sourceLimits.maxErrorPatterns)
          .map(
            (error) => {
              'error_type': _redact(error.errorType),
              'error_message': _redact(error.errorMessage),
              'solution': _redact(error.solution),
              'occurrence_count': error.occurrenceCount,
            },
          )
          .toList(growable: false),
      activeConstraints: activeConstraints.map(_redact).toList(growable: false),
      redaction: const HarnessRedaction(
        applied: true,
        classes: ['secret', 'absolute_private_path', 'raw_transcript'],
      ),
    );
    return packet.compacted(
      maxChars: sourceLimits.maxChars,
      recentTurnsLimit: sourceLimits.recentTurns,
      maxErrorPatterns: sourceLimits.maxErrorPatterns,
    );
  }

  MemoryRuleProposal proposeMemoryCommit({
    required String runId,
    required String fact,
    List<String> evidenceIds = const [],
    DateTime? now,
  }) {
    final createdAt = now ?? DateTime.now().toUtc();
    final redactedFact = _redact(fact);
    return MemoryRuleProposal(
      proposalId: 'mrp_${runId}_${createdAt.millisecondsSinceEpoch}',
      rule: MemoryRule(
        id: 'mr_${runId}_${createdAt.millisecondsSinceEpoch}',
        title: 'Reasoning strategy memory proposal',
        category: 'mobile-harness-reasoning',
        rule: redactedFact,
        source: 'HarnessMemoryPacketService',
        evidenceRepos: evidenceIds,
        createdAt: createdAt,
        enabled: false,
      ),
      rationale:
          'Proposed from non-counted reasoning strategy run; requires approval.',
      evidenceRepos: evidenceIds,
      status: MemoryRuleProposalStatus.pending,
      createdAt: createdAt,
    );
  }

  String _conversationSummary(List<ConversationRecord> conversations) {
    if (conversations.isEmpty) {
      return 'No recent conversation memory available.';
    }
    return _redact(
      conversations
          .map((record) =>
              '${record.timestamp.toIso8601String()}: ${record.userMessage}')
          .join('\n'),
    );
  }
}

String _redact(String value) {
  return value
      .replaceAll(
        RegExp(r'(api[_-]?key|token|secret)\s*[:=]\s*\S+',
            caseSensitive: false),
        r'$1=<redacted>',
      )
      .replaceAll(RegExp(r'/Users/[^ \n\t]+'), '<private_path>')
      .replaceAll(RegExp(r'/Volumes/[^ \n\t]+'), '<private_path>');
}
