import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/services/github_deep_service.dart';
import 'package:mobile_agent/services/github_pages_service.dart';

void main() {
  group('GitHubPagesService.describeFailure', () {
    test('maps unauthorized tokens to login recovery', () {
      final details = GitHubPagesService.describeFailure(const GitHubDeepException(
        message: 'Bad credentials',
        endpoint: '/user',
        statusCode: 401,
      ));

      expect(details.failureKind, 'auth_invalid');
      expect(details.recoveryHint, contains('fresh token'));
    });

    test('maps permission failures to Pages token scope guidance', () {
      final details = GitHubPagesService.describeFailure(const GitHubDeepException(
        message: 'Resource not accessible by personal access token',
        endpoint: '/repos/me/site/pages',
        statusCode: 403,
      ));

      expect(details.failureKind, 'permission_denied');
      expect(details.recoveryHint, contains('Pages read/write'));
      expect(details.recoveryHint, contains('Administration read/write'));
    });

    test('maps validation failures to repo and Pages settings guidance', () {
      final details = GitHubPagesService.describeFailure(const GitHubDeepException(
        message: 'Validation Failed',
        endpoint: '/user/repos',
        statusCode: 422,
      ));

      expect(details.failureKind, 'validation_failed');
      expect(details.recoveryHint, contains('repository name'));
    });
  });
}
