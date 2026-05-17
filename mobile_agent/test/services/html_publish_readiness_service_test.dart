import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/services/html_publish_readiness_service.dart';

void main() {
  group('HtmlPublishReadinessService', () {
    late HtmlPublishReadinessService service;

    setUp(() {
      service = HtmlPublishReadinessService();
    });

    test('accepts a self-contained mobile HTML document', () {
      final report = service.checkHtml('''
<!doctype html>
<html lang="en">
  <head>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>MobileCode Demo</title>
    <style>
      button { min-height: 44px; padding: 12px 16px; }
    </style>
  </head>
  <body>
    <main>
      <button>Play</button>
    </main>
  </body>
</html>
''');

      expect(report.blocked, isFalse);
      expect(report.statusLabel, 'Ready');
      expect(report.warningIssues, isEmpty);
    });

    test('blocks missing title and viewport', () {
      final report = service.checkHtml('<html><body><main>Hello</main></body></html>');

      expect(report.blocked, isTrue);
      expect(report.blockingIssues.map((issue) => issue.code), containsAll(['missing_title', 'missing_viewport']));
    });

    test('blocks leaked app-private paths', () {
      final report = service.checkHtml('''
<html>
  <head>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Leak</title>
  </head>
  <body><main><img src="/data/user/0/com.mobilecode.mobile_agent/app_flutter/index.png" alt="bad"></main></body>
</html>
''');

      expect(report.blocked, isTrue);
      expect(report.blockingIssues.map((issue) => issue.code), contains('private_path_leak'));
    });

    test('warns for remote references unless explicitly allowed', () {
      final report = service.checkHtml('''
<html>
  <head>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Remote</title>
  </head>
  <body><main><script src="https://cdn.example.com/app.js"></script></main></body>
</html>
''');

      expect(report.blocked, isFalse);
      expect(report.warningIssues.map((issue) => issue.code), contains('remote_references'));

      final allowed = service.checkHtml('''
<html>
  <head>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Remote</title>
  </head>
  <body><main><script src="https://cdn.example.com/app.js"></script></main></body>
</html>
''', allowRemoteAssets: true);

      expect(allowed.warningIssues.map((issue) => issue.code), isNot(contains('remote_references')));
    });

    test('warns for accessibility and touch target gaps', () {
      final report = service.checkHtml('''
<html>
  <head>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>A11y</title>
  </head>
  <body><div><button></button><img src="hero.png"></div></body>
</html>
''');

      final codes = report.warningIssues.map((issue) => issue.code);
      expect(codes, contains('unnamed_controls'));
      expect(codes, contains('missing_image_alt'));
      expect(codes, contains('touch_targets_unclear'));
      expect(codes, contains('semantic_structure'));
    });
  });
}
