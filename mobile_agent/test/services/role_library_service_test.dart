import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/services/role_library_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RoleLibraryService proposals', () {
    test('creates, accepts, and dismisses pending role proposals', () async {
      SharedPreferences.setMockInitialValues({});
      final service = RoleLibraryService.instance;
      await service.initialize();

      final proposal = await service.createProposalFromPrompt(
        '帮我研究一个陌生资料目录并提炼复用检查表',
        'run_test_accept',
        service.recruitmentRoles,
      );

      expect(proposal, isNotNull);
      expect(proposal!.status, RoleProposalStatus.pending);
      expect(service.pendingProposals.any((item) => item.proposalId == proposal.proposalId), isTrue);

      await service.acceptProposal(proposal.proposalId);

      expect(service.pendingProposals.any((item) => item.proposalId == proposal.proposalId), isFalse);
      expect(service.allRoles.any((role) => role.id == proposal.role.id && !role.builtIn), isTrue);

      final dismissed = await service.createProposalFromPrompt(
        '帮我梳理冷门素材目录的命名习惯',
        'run_test_dismiss',
        service.recruitmentRoles,
      );

      expect(dismissed, isNotNull);
      await service.dismissProposal(dismissed!.proposalId);

      expect(service.pendingProposals.any((item) => item.proposalId == dismissed.proposalId), isFalse);
      expect(service.allRoles.any((role) => role.id == dismissed.role.id), isFalse);
    });
  });
}
