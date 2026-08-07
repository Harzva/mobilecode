import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/services/mobilecode_update_service.dart';

void main() {
  group('MobileCodeUpdateFeed', () {
    test('parses feed and exposes primary links', () {
      final feed = MobileCodeUpdateFeed.fromJson({
        'schemaVersion': 1,
        'channel': 'stable',
        'title': 'Remote update',
        'message': 'Use GitHub Pages JSON.',
        'latestVersion': '0.1.40',
        'latestBuildNumber': 59,
        'minimumSupportedBuildNumber': 58,
        'pagesUrl': 'https://harzva.github.io/mobilecode/',
        'downloadUrl': 'https://github.com/Harzva/mobilecode/releases/latest',
        'releaseNotes': ['Remote message', 'Pages link'],
      }, sourceUrl: MobileCodeUpdateService.defaultFeedUrl);

      expect(feed.schemaVersion, 1);
      expect(feed.channel, 'stable');
      expect(feed.primaryUrl, 'https://harzva.github.io/mobilecode/');
      expect(
        feed.secondaryUrl,
        'https://github.com/Harzva/mobilecode/releases/latest',
      );
      expect(feed.releaseNotes, hasLength(2));
      expect(
        feed.isNewerThan(currentVersion: '0.1.39', currentBuildNumber: 58),
        isTrue,
      );
      expect(feed.requiresUpgrade(currentBuildNumber: 58), isFalse);
    });

    test('falls back to stable MobileCode links', () {
      final feed = MobileCodeUpdateFeed.fromJson({
        'title': 'Minimal',
      });

      expect(feed.pagesUrl, MobileCodeUpdateService.pagesUrl);
      expect(feed.githubUrl, MobileCodeUpdateService.githubRepoUrl);
      expect(
          feed.latestBuildNumber, MobileCodeUpdateService.currentBuildNumber);
      expect(feed.releaseNotes, isEmpty);
    });

    test('detects required upgrade by minimum build number', () {
      final feed = MobileCodeUpdateFeed.fromJson({
        'latestBuildNumber': 61,
        'minimumSupportedBuildNumber': 60,
      });

      expect(feed.requiresUpgrade(currentBuildNumber: 58), isTrue);
      expect(
        feed.isNewerThan(currentVersion: '0.1.39', currentBuildNumber: 58),
        isTrue,
      );
    });

    test('compares release labels without treating suffix digits as semver',
        () {
      final sameReleaseFeed = MobileCodeUpdateFeed.fromJson({
        'latestVersion': 'v${MobileCodeUpdateService.currentVersion}',
        'latestBuildNumber': MobileCodeUpdateService.currentBuildNumber,
      });
      final currentParts = MobileCodeUpdateService.currentVersion
          .split('.')
          .map(int.parse)
          .toList(growable: false);
      final newerReleaseFeed = MobileCodeUpdateFeed.fromJson({
        'latestVersion':
            'v${currentParts[0]}.${currentParts[1]}.${currentParts[2] + 1}',
        'latestBuildNumber': MobileCodeUpdateService.currentBuildNumber,
      });

      expect(
        sameReleaseFeed.isNewerThan(
          currentVersion: MobileCodeUpdateService.currentVersion,
          currentBuildNumber: MobileCodeUpdateService.currentBuildNumber,
        ),
        isFalse,
      );
      expect(
        newerReleaseFeed.isNewerThan(
          currentVersion: MobileCodeUpdateService.currentVersion,
          currentBuildNumber: MobileCodeUpdateService.currentBuildNumber,
        ),
        isTrue,
      );
    });
  });
}
