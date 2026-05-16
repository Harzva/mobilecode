import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/services/mobile_code_helper_provider.dart';
import 'package:mobile_agent/services/runtime_provider.dart';

void main() {
  group('MobileCodeHelperProvider', () {
    late HttpServer server;
    late Uri baseUri;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      baseUri = Uri.parse('http://127.0.0.1:${server.port}');
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('reads helper health and capabilities', () async {
      _serve((request) async {
        expect(request.uri.path, '/v1/health');
        await _json(request.response, {
          'name': 'Test Helper',
          'available': true,
          'ready': true,
          'status': 'ready',
          'capabilities': {
            'shell': true,
            'git': true,
            'pty': true,
            'backgroundService': true,
          },
        });
      }, server);

      final provider = MobileCodeHelperProvider(baseUri: baseUri);
      final health = await provider.healthCheck();

      expect(health.type, RuntimeProviderType.mobileCodeHelper);
      expect(health.name, 'Test Helper');
      expect(health.ready, isTrue);
      expect(health.capabilities.shell, isTrue);
      expect(health.capabilities.pty, isTrue);
    });

    test('executes commands through helper protocol', () async {
      _serve((request) async {
        expect(request.uri.path, '/v1/execute');
        final body = await utf8.decoder.bind(request).join();
        final payload = jsonDecode(body) as Map<String, dynamic>;
        expect(payload['command'], 'pwd');
        await _json(request.response, {
          'command': payload['command'],
          'stdout': '/workspace\n',
          'stderr': '',
          'exitCode': 0,
          'durationMs': 12,
        });
      }, server);

      final provider = MobileCodeHelperProvider(baseUri: baseUri);
      final result = await provider.execute('pwd');

      expect(result.success, isTrue);
      expect(result.stdout, '/workspace\n');
      expect(result.duration.inMilliseconds, 12);
    });

    test('streams NDJSON helper output', () async {
      _serve((request) async {
        expect(request.uri.path, '/v1/execute/stream');
        request.response.headers.contentType = ContentType('application', 'x-ndjson');
        request.response.writeln(jsonEncode({'type': 'stdout', 'data': 'hello'}));
        request.response.writeln(jsonEncode({'type': 'stderr', 'data': 'warn'}));
        request.response.writeln(jsonEncode({'type': 'exit', 'exitCode': 0}));
        await request.response.close();
      }, server);

      final provider = MobileCodeHelperProvider(baseUri: baseUri);
      final lines = await provider.executeStream('echo hello').toList();

      expect(lines, ['hello', '[stderr] warn', '[exit] Helper command exited with code 0']);
    });

    test('restores current helper task snapshot', () async {
      _serve((request) async {
        expect(request.uri.path, '/v1/tasks/current');
        await _json(request.response, {
          'running': false,
          'taskId': 'task-123',
          'command': 'npm test',
          'logs': ['stdout: ok'],
          'task': {
            'id': 'task-123',
            'command': 'npm test',
            'cwd': '/workspace/app',
            'status': 'succeeded',
            'startedAtMs': 1700000000000,
            'finishedAtMs': 1700000001000,
            'exitCode': 0,
            'durationMs': 1000,
            'logs': ['stdout: ok'],
          },
        });
      }, server);

      final provider = MobileCodeHelperProvider(baseUri: baseUri);
      final task = await provider.currentTask();

      expect(task, isNotNull);
      expect(task!.taskId, 'task-123');
      expect(task.status, RuntimeTaskStatus.succeeded);
      expect(task.command, 'npm test');
      expect(task.workingDir, '/workspace/app');
      expect(task.duration, const Duration(seconds: 1));
      expect(task.logs, ['stdout: ok']);
    });
  });
}

void _serve(
  Future<void> Function(HttpRequest request) handler,
  HttpServer server,
) {
  server.listen((request) {
    handler(request);
  });
}

Future<void> _json(HttpResponse response, Map<String, dynamic> payload) async {
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode(payload));
  await response.close();
}
