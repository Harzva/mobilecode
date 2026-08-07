import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/core/mobilecode_version.dart';
import 'package:mobile_agent/services/mobilecode_update_service.dart';

void main() {
  test('package metadata, update service, and published feed stay aligned', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final feed = jsonDecode(
      File('../docs/mobilecode-update.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    expect(
      pubspec,
      contains(
        'version: ${MobileCodeVersion.semantic}+'
        '${MobileCodeVersion.buildNumber}',
      ),
    );
    expect(
      MobileCodeUpdateService.currentVersion,
      MobileCodeVersion.semantic,
    );
    expect(
      MobileCodeUpdateService.currentBuildNumber,
      MobileCodeVersion.buildNumber,
    );
    expect(feed['latestVersion'], MobileCodeVersion.tag);
    expect(feed['latestBuildNumber'], MobileCodeVersion.buildNumber);
    expect(feed['releaseUrl'], MobileCodeVersion.releaseUrl);
    expect(feed['downloadUrl'], MobileCodeVersion.androidDownloadUrl);
  });
}
