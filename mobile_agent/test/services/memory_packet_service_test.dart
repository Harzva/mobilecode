import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/services/memory_packet_service.dart';
import 'package:mobile_agent/services/memory_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('HarnessMemoryPacketService', () {
    test(
        'builds compact redacted packet from MemoryService without raw transcript',
        () async {
      SharedPreferences.setMockInitialValues({});
      final memory = MemoryService();
      await memory.init();
      await memory.addConversation(
        ConversationRecord(
          id: 'conv-1',
          timestamp: DateTime.utc(2026, 6, 20, 10),
          userMessage: 'token=abc123 please remember /Volumes/private/project',
          aiResponse: 'api_key: xyz789 response with raw details',
          tags: const ['mobile'],
        ),
      );
      await memory.recordErrorPattern(
        ErrorPattern(
          id: 'err-1',
          errorType: 'flutter_test_failure',
          errorMessage: 'Retry finalStatus failed',
          solution: 'Use latest verification per step',
          occurrenceCount: 1,
          lastOccurred: DateTime.utc(2026, 6, 20),
        ),
      );
      await memory.upsertProjectMemory(
        ProjectMemory(
          id: 'proj-1',
          projectId: 'mobile-code',
          projectName: 'MobileCode',
          indexedFiles: 10,
          indexedFunctions: 20,
          indexedClasses: 5,
          lastIndexed: DateTime.utc(2026, 6, 20),
          indexSizeKB: 12,
        ),
      );

      final packet =
          await HarnessMemoryPacketService(memoryService: memory).buildPacket(
        userGoal: 'Implement strategy dispatcher',
        sessionId: 'session-memory',
        runId: 'run-memory',
        now: DateTime.utc(2026, 6, 20, 12),
        sourceLimits: const HarnessSourceLimits(
            recentTurns: 1, maxChars: 220, maxErrorPatterns: 1),
      );

      final json = packet.toJson().toString();
      expect(packet.recentTurns, hasLength(1));
      expect(packet.errorPatterns, hasLength(1));
      expect(packet.projectFacts.single['project_name'], 'MobileCode');
      expect(packet.redaction.applied, isTrue);
      expect(json, isNot(contains('abc123')));
      expect(json, isNot(contains('xyz789')));
      expect(json, isNot(contains('/Volumes/private')));
      expect(packet.isExpired(DateTime.utc(2026, 6, 21, 13)), isTrue);
    });

    test('creates memory commit proposal payload without persisting rules',
        () async {
      SharedPreferences.setMockInitialValues({});
      final memory = MemoryService();
      await memory.init();
      final service = HarnessMemoryPacketService(memoryService: memory);

      final proposal = service.proposeMemoryCommit(
        runId: 'run-memory',
        fact: 'Prefer non-counted dry-run strategy traces before real pilots.',
        evidenceIds: const ['ev-1'],
      );

      expect(proposal.status.name, 'pending');
      expect(proposal.rule.rule, contains('Prefer non-counted'));
      expect(await memory.getMemoryRules(), isEmpty);
      expect(await memory.pendingMemoryRuleProposals(), isEmpty);
    });
  });
}
