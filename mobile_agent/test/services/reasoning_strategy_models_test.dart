import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/services/reasoning_strategy_models.dart';

void main() {
  group('HarnessMemoryPacket', () {
    test('roundtrips JSON with redaction metadata', () {
      final packet = _sampleMemoryPacket();

      final json = packet.toJson();
      final restored = HarnessMemoryPacket.fromJson(json);

      expect(restored.packetId, packet.packetId);
      expect(restored.schemaVersion, '0.1.0');
      expect(restored.sessionId, 'session-1');
      expect(restored.runId, 'run-1');
      expect(restored.redaction.applied, isTrue);
      expect(restored.redaction.classes, containsAll(['secret', 'token']));
      expect(restored.recentTurns, hasLength(3));
      expect(restored.projectFacts.first['fact'], 'repo uses Flutter/Dart');
    });

    test('supports TTL expiry checks', () {
      final createdAt = DateTime.utc(2026, 1, 1);
      final packet = _sampleMemoryPacket(createdAt: createdAt, ttlSeconds: 60);

      expect(packet.isExpired(createdAt.add(const Duration(seconds: 59))), isFalse);
      expect(packet.isExpired(createdAt.add(const Duration(seconds: 60))), isTrue);
    });

    test('enforces recent-turn and max-character compaction limits', () {
      final packet = _sampleMemoryPacket(
        turns: List<HarnessRecentTurn>.generate(
          5,
          (index) => HarnessRecentTurn(
            role: 'user',
            summary: 'turn-$index-${List.filled(30, 'x').join()}',
            evidenceIds: ['ev-$index'],
          ),
        ),
      );

      final compacted = packet.compacted(maxChars: 80, recentTurnsLimit: 2, maxErrorPatterns: 1);
      final jsonText = compacted.toJson().toString();

      expect(compacted.recentTurns, hasLength(2));
      expect(compacted.recentTurns.first.evidenceIds, ['ev-3']);
      expect(compacted.sourceLimits.maxChars, 80);
      expect(compacted.errorPatterns, hasLength(1));
      expect(jsonText.length, lessThan(packet.toJson().toString().length));
    });
  });

  group('HandoffPacket', () {
    test('roundtrips JSON and removes raw transcript by default', () {
      final packet = HandoffPacket(
        handoffId: 'hoff-1',
        fromRole: 'Supervisor',
        toRole: 'CodeAgent',
        reason: 'step requires patching',
        priority: 'normal',
        stepId: 'step_001',
        task: 'patch fake artifact',
        inputFilter: HandoffInputFilter.removeToolCalls,
        allowedTools: const ['read_file', 'apply_patch'],
        forbiddenTools: const ['raw_shell'],
        context: const {
          'goal_summary': 'compact goal',
          'raw_transcript': 'must not leak',
          'tool_calls': ['must not leak'],
          'evidence_ids': ['ev-1'],
          'role_context': {
            'CodeAgent': {'artifact_paths': ['lib/main.dart']},
          },
        },
      );

      final json = packet.toJson();
      final context = json['context'] as Map<String, dynamic>;

      expect(context.containsKey('raw_transcript'), isFalse);
      expect(context.containsKey('tool_calls'), isFalse);
      expect(context['artifact_paths'], ['lib/main.dart']);
      expect(json['input_filter'], 'remove_tool_calls');

      final restored = HandoffPacket.fromJson(json);
      expect(restored.handoffId, 'hoff-1');
      expect(restored.inputFilter, HandoffInputFilter.removeToolCalls);
      expect(restored.returnContract.noRawSecretEcho, isTrue);
    });

    test('supports evidence_refs_only input filter', () {
      final packet = HandoffPacket(
        handoffId: 'hoff-2',
        fromRole: 'Supervisor',
        toRole: 'VerifierAgent',
        reason: 'verify fake evidence',
        priority: 'high',
        stepId: 'step_002',
        task: 'verify',
        inputFilter: HandoffInputFilter.evidenceRefsOnly,
        context: const {
          'goal_summary': 'compact goal',
          'summary': 'should be excluded by evidence-only filter',
          'evidence_ids': ['ev-2'],
          'artifact_paths': ['out.html'],
          'transcript': 'must not leak',
        },
      );

      final context = packet.toJson()['context'] as Map<String, dynamic>;
      expect(context.keys, containsAll(['goal_summary', 'evidence_ids', 'artifact_paths']));
      expect(context.containsKey('summary'), isFalse);
      expect(context.containsKey('transcript'), isFalse);
    });
  });

  group('StrategyTrace and StepVerification', () {
    test('roundtrips benchmark-friendly JSON', () {
      final trace = StrategyTrace(
        traceId: 'strace-1',
        strategyId: 'plan_execute_verify_single_agent',
        traceStatus: StrategyTraceStatus.scaffoldNotRun,
      );
      trace.appendEvent(
        StrategyTraceEvent(
          eventId: 'evt_001',
          type: StrategyEventType.plan,
          role: 'PlannerAgent',
          stepId: 'step_001',
          startedAt: DateTime.utc(2026, 1, 1),
          endedAt: DateTime.utc(2026, 1, 1, 0, 0, 0, 1),
          summary: 'fake plan',
        ),
      );
      trace.appendEvent(
        StrategyTraceEvent(
          eventId: 'evt_002',
          type: StrategyEventType.handoff,
          role: 'Supervisor',
          stepId: 'step_001',
          startedAt: DateTime.utc(2026, 1, 1, 0, 0, 1),
          summary: 'fake handoff',
        ),
      );

      final restored = StrategyTrace.fromJson(trace.toBenchmarkJson());

      expect(restored.events.map((event) => event.type), [
        StrategyEventType.plan,
        StrategyEventType.handoff,
      ]);
      expect(restored.handoffCount, 1);
      expect(restored.toJson()['counts_as_experiment'], isFalse);
    });

    test('roundtrips StepVerification and shouldRetry contract', () {
      const verification = StepVerification(
        stepId: 'step_001',
        status: StepVerificationStatus.fail,
        confidence: 0.25,
        checks: [
          StepVerificationCheck(
            name: 'artifact_exists',
            status: StepVerificationStatus.fail,
            evidenceId: 'ev-1',
          ),
        ],
        issues: ['missing artifact'],
        critique: 'create the expected artifact',
        retryAllowed: true,
        retryCount: 0,
        evidenceIds: ['ev-1'],
      );

      final restored = StepVerification.fromJson(verification.toJson());

      expect(restored.status, StepVerificationStatus.fail);
      expect(restored.shouldRetry, isTrue);
      expect(restored.countsAsVerifiedSuccess, isFalse);
      expect(restored.toJson()['status'], 'fail');
    });
  });
}

HarnessMemoryPacket _sampleMemoryPacket({
  DateTime? createdAt,
  int ttlSeconds = 86400,
  List<HarnessRecentTurn>? turns,
}) {
  return HarnessMemoryPacket(
    packetId: 'hmp-run-1-turn-1',
    schemaVersion: '0.1.0',
    sessionId: 'session-1',
    runId: 'run-1',
    createdAt: createdAt ?? DateTime.utc(2026, 1, 1),
    ttlSeconds: ttlSeconds,
    sourceLimits: const HarnessSourceLimits(
      recentTurns: 12,
      maxChars: 12000,
      maxErrorPatterns: 5,
    ),
    userGoal: 'Implement fake reasoning strategy runner',
    conversationSummary: 'Compact non-raw summary',
    recentTurns: turns ??
        const [
          HarnessRecentTurn(role: 'user', summary: 'asked for P1/P2', evidenceIds: ['ev-a']),
          HarnessRecentTurn(role: 'assistant', summary: 'planned local-only work', evidenceIds: ['ev-b']),
          HarnessRecentTurn(role: 'tool', summary: 'read contract docs', evidenceIds: ['ev-c']),
        ],
    projectFacts: const [
      {'fact': 'repo uses Flutter/Dart', 'source': 'project_summary', 'confidence': 0.9},
    ],
    userPreferences: const [
      {'preference': 'do not fake counted benchmark results'},
    ],
    errorPatterns: const [
      {'pattern': 'missing verifier evidence', 'fix': 'mark as dry_run_not_counted'},
      {'pattern': 'raw transcript leak', 'fix': 'use summary_only handoff filter'},
    ],
    activeConstraints: const [
      'no network',
      'no real model',
      'no counted result without evidence',
    ],
    redaction: const HarnessRedaction(
      applied: true,
      classes: ['secret', 'token'],
    ),
  );
}
