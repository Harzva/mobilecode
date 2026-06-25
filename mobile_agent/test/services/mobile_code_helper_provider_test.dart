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

    test('does not claim an external Termux daemon as Helper APK', () async {
      _serve((request) async {
        expect(request.uri.path, '/v1/health');
        await _json(request.response, {
          'name': 'MobileCode Helper Prototype',
          'available': true,
          'ready': true,
          'status': 'Helper daemon running in Termux',
          'runtimeKind': 'termuxDaemon',
          'termux': true,
          'capabilities': {'shell': true, 'git': true},
        });
      }, server);

      final provider = MobileCodeHelperProvider(baseUri: baseUri);
      final health = await provider.healthCheck();

      expect(health.available, isFalse);
      expect(health.ready, isFalse);
      expect(health.status, contains('External Termux daemon'));
    });

    test('accepts external Termux daemon health as a strong runtime', () async {
      _serve((request) async {
        expect(request.uri.path, '/v1/health');
        await _json(request.response, {
          'name': 'MobileCode Helper Prototype',
          'available': true,
          'ready': true,
          'status': 'Helper daemon running in Termux',
          'runtimeKind': 'termuxDaemon',
          'termux': true,
          'workspaceRoot': '/data/data/com.termux/files/home/mobilecode',
          'capabilities': {
            'shell': true,
            'git': true,
            'processStreaming': true,
            'backgroundService': true,
          },
        });
      }, server);

      final provider = TermuxDaemonProvider(baseUri: baseUri);
      final health = await provider.healthCheck();

      expect(health.type, RuntimeProviderType.externalTermux);
      expect(health.ready, isTrue);
      expect(health.capabilities.git, isTrue);
      expect(health.status, contains('Termux daemon is running'));
      expect(
        provider.workspaceRoot,
        '/data/data/com.termux/files/home/mobilecode',
      );
    });

    test('sends helper auth token header when configured', () async {
      _serve((request) async {
        expect(request.uri.path, '/v1/health');
        expect(request.headers.value('X-MobileCode-Token'), 'test-token');
        await _json(request.response, {
          'name': 'Token Helper',
          'available': true,
          'ready': true,
          'status': 'ready',
          'authRequired': true,
          'capabilities': {'shell': true},
        });
      }, server);

      final provider =
          MobileCodeHelperProvider(baseUri: baseUri, authToken: 'test-token');
      final health = await provider.healthCheck();

      expect(health.ready, isTrue);
      expect(health.capabilities.shell, isTrue);
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
        request.response.headers.contentType =
            ContentType('application', 'x-ndjson');
        request.response
            .writeln(jsonEncode({'type': 'stdout', 'data': 'hello'}));
        request.response
            .writeln(jsonEncode({'type': 'stderr', 'data': 'warn'}));
        request.response.writeln(jsonEncode({'type': 'exit', 'exitCode': 0}));
        await request.response.close();
      }, server);

      final provider = MobileCodeHelperProvider(baseUri: baseUri);
      final lines = await provider.executeStream('echo hello').toList();

      expect(lines, [
        'hello',
        '[stderr] warn',
        '[exit] Helper command exited with code 0'
      ]);
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

    test('lists helper task history and recovers task logs', () async {
      var requestCount = 0;
      _serve((request) async {
        requestCount += 1;
        if (requestCount == 1) {
          expect(request.uri.path, '/v1/tasks');
          expect(request.uri.queryParameters['limit'], '5');
          await _json(request.response, {
            'tasks': [
              {
                'id': 'task-failed',
                'command': 'npm test',
                'cwd': '/workspace/app',
                'status': 'failed',
                'exitCode': 1,
                'durationMs': 25,
                'failureKind': 'processFailed',
                'logs': ['stderr: failed'],
              },
            ],
            'count': 1,
          });
          return;
        }

        expect(request.uri.path, '/v1/tasks/task-failed/logs');
        expect(request.uri.queryParameters['limit'], '10');
        await _json(request.response, {
          'taskId': 'task-failed',
          'logs': ['stdout: start', 'stderr: failed'],
        });
      }, server);

      final provider = MobileCodeHelperProvider(baseUri: baseUri);
      final tasks = await provider.listTasks(limit: 5);
      final logs = await provider.taskLogs('task-failed', limit: 10);

      expect(tasks, hasLength(1));
      expect(tasks.first.taskId, 'task-failed');
      expect(tasks.first.failureKind, RuntimeTaskFailureKind.processFailed);
      expect(logs, ['stdout: start', 'stderr: failed']);
    });

    test('sends helper stop request for active task cancellation', () async {
      _serve((request) async {
        expect(request.uri.path, '/v1/task/stop');
        expect(request.method, 'POST');
        await _json(request.response, {
          'success': true,
          'stopped': true,
        });
      }, server);

      final provider = MobileCodeHelperProvider(baseUri: baseUri);

      await provider.stopCurrentTask();
    });

    test('sends helper stop request for a task id', () async {
      _serve((request) async {
        expect(request.uri.path, '/v1/tasks/task-123/stop');
        expect(request.method, 'POST');
        await _json(request.response, {
          'success': true,
          'stopped': true,
          'taskId': 'task-123',
        });
      }, server);

      final provider = MobileCodeHelperProvider(baseUri: baseUri);

      await provider.stopTask('task-123');
    });

    test('preflights project markers through helper protocol', () async {
      var requestCount = 0;
      _serve((request) async {
        requestCount += 1;
        if (requestCount == 1) {
          expect(request.uri.path, '/v1/project/preflight');
          final body = await utf8.decoder.bind(request).join();
          final payload = jsonDecode(body) as Map<String, dynamic>;
          expect(payload['cwd'], '/workspace/app');
          await _json(request.response, {
            'success': true,
            'cwd': '/workspace/app',
            'detectedFiles': ['./package.json', './.git'],
          });
          return;
        }

        expect(request.uri.path, '/v1/health');
        await _json(request.response, {
          'name': 'Test Helper',
          'available': true,
          'ready': true,
          'status': 'ready',
          'capabilities': {
            'shell': true,
            'node': true,
            'git': true,
          },
        });
      }, server);

      final provider = MobileCodeHelperProvider(baseUri: baseUri);
      final profile = await provider.preflightProject('/workspace/app');

      expect(profile.packageManager, 'npm');
      expect(profile.hasGit, isTrue);
      expect(profile.detectedFiles, ['./.git', './package.json']);
    });

    test('starts typed termux task through helper protocol', () async {
      _serve((request) async {
        expect(request.uri.path, '/v1/task/start');
        expect(request.method, 'POST');
        final body = await utf8.decoder.bind(request).join();
        final payload = jsonDecode(body) as Map<String, dynamic>;
        expect(payload['taskKind'], 'project_check');
        expect(payload['path'], '.');
        expect(payload['args'], {'entry': 'index.html'});
        await _json(request.response, {
          'success': true,
          'taskId': 'typed-123',
          'taskKind': 'project_check',
          'status': 'succeeded',
          'stdout': '{"detectedFiles":["./package.json"]}',
          'stderr': '',
          'exitCode': 0,
          'durationMs': 10,
          'failureKind': 'none',
        });
      }, server);

      final provider = MobileCodeHelperProvider(baseUri: baseUri);
      final result = await provider.runTermuxTask(
        taskKind: 'project_check',
        payload: const {
          'path': '.',
          'args': {'entry': 'index.html'},
        },
      );

      expect(result['taskId'], 'typed-123');
      expect(result['status'], 'succeeded');
      expect(result['exitCode'], 0);
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
