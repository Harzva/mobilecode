// lib/services/mobile_code_helper_provider.dart
// RuntimeProvider client for the future MobileCode Helper daemon.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'runtime_actions.dart';
import 'runtime_provider.dart';
import 'termux_service.dart';

/// HTTP/NDJSON client for a local MobileCode Helper daemon.
///
/// Protocol v1:
/// - GET  /v1/health
/// - POST /v1/execute
/// - POST /v1/execute/stream       (NDJSON lines)
/// - POST /v1/sync
/// - POST /v1/build/web
/// - POST /v1/build/apk
/// - POST /v1/apk/install
/// - POST /v1/app/launch
/// - POST /v1/app/uninstall
/// - POST /v1/task/stop
/// - GET  /v1/tasks/current
/// - GET  /v1/tasks
/// - GET  /v1/tasks/:id/logs
/// - POST /v1/project/preflight
class MobileCodeHelperProvider implements RuntimeProvider, RuntimeTaskMonitor, RuntimeProjectInspector {
  final Uri baseUri;
  final Duration probeTimeout;
  final String? authToken;
  final HttpClient _client;
  final StreamController<String> _logController = StreamController<String>.broadcast();

  RuntimeHealth? _lastHealth;

  MobileCodeHelperProvider({
    Uri? baseUri,
    this.probeTimeout = const Duration(milliseconds: 700),
    this.authToken,
    HttpClient? client,
  })  : baseUri = baseUri ?? Uri.parse('http://127.0.0.1:8765'),
        _client = client ?? HttpClient();

  @override
  RuntimeProviderType get type => RuntimeProviderType.mobileCodeHelper;

  @override
  String get name => 'MobileCode Helper';

  @override
  Stream<String> get logStream => _logController.stream;

  @override
  Future<void> initialize() async {
    _client.connectionTimeout = probeTimeout;
  }

  @override
  Future<RuntimeCapabilities> capabilities() async {
    final health = _lastHealth ?? await healthCheck();
    return health.capabilities;
  }

  @override
  Future<RuntimeHealth> healthCheck() async {
    try {
      final payload = await _getJson('/v1/health', timeout: probeTimeout);
      final capabilities = _capabilitiesFromJson(_mapValue(payload['capabilities']));
      final health = RuntimeHealth(
        type: type,
        name: (payload['name'] as String?) ?? name,
        available: payload['available'] as bool? ?? true,
        ready: payload['ready'] as bool? ?? false,
        status: (payload['status'] as String?) ?? 'MobileCode Helper responded.',
        capabilities: capabilities,
        missingDependencies: _stringList(payload['missingDependencies']),
        recoveryActions: _stringList(payload['recoveryActions']),
      );
      _lastHealth = health;
      return health;
    } catch (e) {
      final health = RuntimeHealth(
        type: type,
        name: name,
        available: false,
        ready: false,
        status: 'MobileCode Helper daemon is not reachable at $baseUri.',
        capabilities: RuntimeCapabilities.none,
        missingDependencies: const ['MobileCode Helper daemon'],
        recoveryActions: const [
          'Install or start the MobileCode Helper APK.',
          'For the prototype, run mobile_agent/tooling/run_mobilecode_helper_daemon.sh in Termux.',
          'Keep the helper foreground service or daemon running before retrying.',
        ],
      );
      _lastHealth = health;
      return health;
    }
  }

  @override
  Future<RuntimeCommandResult> execute(
    String command, {
    String? workingDir,
    Map<String, String>? environment,
    Duration? timeout,
  }) async {
    final stopwatch = Stopwatch()..start();
    final payload = await _postJson('/v1/execute', {
      'command': command,
      if (workingDir != null) 'cwd': workingDir,
      if (environment != null) 'env': environment,
      if (timeout != null) 'timeoutMs': timeout.inMilliseconds,
    }, timeout: timeout);
    stopwatch.stop();

    return RuntimeCommandResult(
      command: (payload['command'] as String?) ?? command,
      stdout: (payload['stdout'] as String?) ?? '',
      stderr: (payload['stderr'] as String?) ?? '',
      exitCode: (payload['exitCode'] as num?)?.toInt() ?? 1,
      duration: Duration(
        milliseconds: (payload['durationMs'] as num?)?.toInt() ??
            stopwatch.elapsedMilliseconds,
      ),
      providerType: type,
      taskId: payload['taskId'] as String?,
      failureKind: _taskFailureKindFromString(payload['failureKind']?.toString()),
    );
  }

  @override
  Future<RuntimeTaskSnapshot?> currentTask() async {
    final payload = await _getJson('/v1/tasks/current', timeout: const Duration(seconds: 3));
    final taskPayload = payload['task'];
    if (taskPayload is Map) {
      return _taskSnapshotFromJson(Map<String, dynamic>.from(taskPayload));
    }

    final taskId = payload['taskId']?.toString() ?? '';
    final command = payload['command']?.toString() ?? '';
    final logs = _stringList(payload['logs']);
    if (taskId.isEmpty && command.isEmpty && logs.isEmpty) return null;
    return RuntimeTaskSnapshot(
      taskId: taskId,
      status: payload['running'] == true ? RuntimeTaskStatus.running : RuntimeTaskStatus.unknown,
      command: command,
      logs: logs,
      providerType: type,
    );
  }

  @override
  Future<List<RuntimeTaskSnapshot>> listTasks({int limit = 20}) async {
    final payload = await _getJson('/v1/tasks?limit=$limit', timeout: const Duration(seconds: 3));
    final tasks = payload['tasks'];
    if (tasks is! List) return const [];
    return tasks
        .whereType<Map>()
        .map((task) => _taskSnapshotFromJson(Map<String, dynamic>.from(task)))
        .toList();
  }

  @override
  Future<List<String>> taskLogs(String taskId, {int limit = 200}) async {
    final safeTaskId = Uri.encodeComponent(taskId);
    final payload = await _getJson('/v1/tasks/$safeTaskId/logs?limit=$limit', timeout: const Duration(seconds: 3));
    return _stringList(payload['logs']);
  }

  @override
  Future<RuntimeProjectProfile> preflightProject(
    String projectPath, {
    String? packageManager,
  }) async {
    final payload = await _postJson('/v1/project/preflight', {
      'cwd': projectPath,
      if (packageManager != null) 'packageManager': packageManager,
    }, timeout: const Duration(seconds: 8));
    final detectedFiles = _stringList(payload['detectedFiles']);
    final caps = await capabilities();
    return profileRuntimeProject(
      projectPath: payload['cwd']?.toString() ?? projectPath,
      probeOutput: detectedFiles.join('\n'),
      capabilities: caps,
      packageManagerOverride: packageManager,
    );
  }

  @override
  Stream<String> executeStream(
    String command, {
    String? workingDir,
    Map<String, String>? environment,
  }) async* {
    final request = await _openPost('/v1/execute/stream', {
      'command': command,
      if (workingDir != null) 'cwd': workingDir,
      if (environment != null) 'env': environment,
    }, accept: 'application/x-ndjson');

    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.transform(utf8.decoder).join();
      yield '[error] Helper stream failed: HTTP ${response.statusCode} $body';
      return;
    }

    await for (final line in response
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
      final decoded = jsonDecode(line);
      if (decoded is! Map<String, dynamic>) {
        yield line;
        continue;
      }
      final type = decoded['type'] as String? ?? 'stdout';
      final data = decoded['data']?.toString() ?? '';
      if (type == 'exit') {
        final exitCode = decoded['exitCode']?.toString() ?? 'unknown';
        final message = '[exit] Helper command exited with code $exitCode';
        _logController.add(message);
        yield message;
      } else {
        final message = type == 'stderr' ? '[stderr] $data' : data;
        _logController.add(message);
        yield message;
      }
    }
  }

  @override
  Future<RuntimeSyncResult> syncWorkspace({
    required String sourcePath,
    required String targetPath,
  }) async {
    final payload = await _postJson('/v1/sync', {
      'sourcePath': sourcePath,
      'targetPath': targetPath,
    });
    return RuntimeSyncResult(
      success: payload['success'] as bool? ?? false,
      sourcePath: (payload['sourcePath'] as String?) ?? sourcePath,
      targetPath: (payload['targetPath'] as String?) ?? targetPath,
      error: payload['error'] as String?,
    );
  }

  @override
  Future<BuildResult> buildWeb(String projectPath) async {
    final payload = await _postJson('/v1/build/web', {'projectPath': projectPath});
    return _buildResultFromJson(payload);
  }

  @override
  Future<BuildResult> buildApk(String projectPath, {BuildMode mode = BuildMode.debug}) async {
    final payload = await _postJson('/v1/build/apk', {
      'projectPath': projectPath,
      'mode': mode.name,
    });
    return _buildResultFromJson(payload);
  }

  @override
  Future<InstallResult> installApk(String apkPath) async {
    final payload = await _postJson('/v1/apk/install', {'apkPath': apkPath});
    return InstallResult(
      success: payload['success'] as bool? ?? false,
      packageName: (payload['packageName'] as String?) ?? '',
      error: payload['error'] as String?,
    );
  }

  @override
  Future<void> launchApp(String packageName) async {
    await _postJson('/v1/app/launch', {'packageName': packageName});
  }

  @override
  Future<void> uninstallApp(String packageName) async {
    await _postJson('/v1/app/uninstall', {'packageName': packageName});
  }

  @override
  Future<void> stopCurrentTask() async {
    await _postJson('/v1/task/stop', const {});
  }

  Uri _resolve(String path) => baseUri.resolve(path);

  Future<Map<String, dynamic>> _getJson(String path, {Duration? timeout}) async {
    final request = await _client.getUrl(_resolve(path)).timeout(timeout ?? probeTimeout);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    _attachAuth(request);
    return _decodeJsonResponse(await request.close().timeout(timeout ?? probeTimeout));
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body, {
    Duration? timeout,
  }) async {
    final request = await _openPost(path, body).timeout(timeout ?? const Duration(seconds: 120));
    return _decodeJsonResponse(await request.close().timeout(timeout ?? const Duration(seconds: 120)));
  }

  Future<HttpClientRequest> _openPost(
    String path,
    Map<String, dynamic> body, {
    String accept = 'application/json',
  }) async {
    final request = await _client.postUrl(_resolve(path));
    request.headers.set(HttpHeaders.acceptHeader, accept);
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    _attachAuth(request);
    request.write(jsonEncode(body));
    return request;
  }

  void _attachAuth(HttpClientRequest request) {
    final token = authToken?.trim();
    if (token == null || token.isEmpty) return;
    request.headers.set('X-MobileCode-Token', token);
  }

  Future<Map<String, dynamic>> _decodeJsonResponse(HttpClientResponse response) async {
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MobileCodeHelperException('HTTP ${response.statusCode}: $text');
    }
    if (text.trim().isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) return decoded;
    throw const MobileCodeHelperException('Helper response was not a JSON object.');
  }

  RuntimeCapabilities _capabilitiesFromJson(Map<String, dynamic> json) {
    return RuntimeCapabilities(
      shell: json['shell'] as bool? ?? false,
      git: json['git'] as bool? ?? false,
      node: json['node'] as bool? ?? false,
      python: json['python'] as bool? ?? false,
      flutter: json['flutter'] as bool? ?? false,
      androidBuild: json['androidBuild'] as bool? ?? false,
      pty: json['pty'] as bool? ?? false,
      backgroundService: json['backgroundService'] as bool? ?? false,
      webViewPreview: json['webViewPreview'] as bool? ?? false,
      cloudBuild: json['cloudBuild'] as bool? ?? false,
    );
  }

  BuildResult _buildResultFromJson(Map<String, dynamic> json) {
    return BuildResult(
      success: json['success'] as bool? ?? false,
      outputPath: json['outputPath'] as String?,
      error: json['error'] as String?,
      buildTime: Duration(milliseconds: (json['buildTimeMs'] as num?)?.toInt() ?? 0),
      fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
    );
  }

  RuntimeTaskSnapshot _taskSnapshotFromJson(Map<String, dynamic> json) {
    final durationMs = (json['durationMs'] as num?)?.toInt();
    return RuntimeTaskSnapshot(
      taskId: json['id']?.toString() ?? json['taskId']?.toString() ?? '',
      status: _taskStatusFromString(json['status']?.toString()),
      command: json['command']?.toString() ?? '',
      workingDir: json['cwd']?.toString() ?? json['workingDir']?.toString(),
      startedAt: _dateFromEpochMs(json['startedAtMs']),
      finishedAt: _dateFromEpochMs(json['finishedAtMs']),
      exitCode: (json['exitCode'] as num?)?.toInt(),
      duration: durationMs == null ? null : Duration(milliseconds: durationMs),
      logs: _stringList(json['logs']),
      providerType: type,
      error: json['error']?.toString(),
      failureKind: _taskFailureKindFromString(json['failureKind']?.toString()),
    );
  }

  RuntimeTaskStatus _taskStatusFromString(String? value) {
    return switch (value) {
      'queued' => RuntimeTaskStatus.queued,
      'running' => RuntimeTaskStatus.running,
      'succeeded' => RuntimeTaskStatus.succeeded,
      'failed' => RuntimeTaskStatus.failed,
      'cancelled' => RuntimeTaskStatus.cancelled,
      'timedOut' || 'timed_out' || 'timeout' => RuntimeTaskStatus.timedOut,
      'lost' => RuntimeTaskStatus.lost,
      _ => RuntimeTaskStatus.unknown,
    };
  }

  RuntimeTaskFailureKind _taskFailureKindFromString(String? value) {
    if (value == null || value == 'none') return RuntimeTaskFailureKind.none;
    return switch (value) {
      'timeout' || 'timedOut' || 'timed_out' => RuntimeTaskFailureKind.timeout,
      'cancelled' => RuntimeTaskFailureKind.cancelled,
      'dependencyMissing' || 'dependency_missing' => RuntimeTaskFailureKind.dependencyMissing,
      'commandBlocked' || 'command_blocked' => RuntimeTaskFailureKind.commandBlocked,
      'cwdOutsideWorkspace' || 'cwd_outside_workspace' => RuntimeTaskFailureKind.cwdOutsideWorkspace,
      'authFailed' || 'auth_failed' => RuntimeTaskFailureKind.authFailed,
      'processFailed' || 'process_failed' => RuntimeTaskFailureKind.processFailed,
      'runtimeLost' || 'runtime_lost' || 'lost' => RuntimeTaskFailureKind.runtimeLost,
      _ => RuntimeTaskFailureKind.unknown,
    };
  }

  DateTime? _dateFromEpochMs(Object? value) {
    final millis = (value as num?)?.toInt();
    if (millis == null || millis <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  Map<String, dynamic> _mapValue(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }

  List<String> _stringList(Object? value) {
    if (value is List) return value.map((item) => item.toString()).toList();
    return const [];
  }
}

class MobileCodeHelperException implements Exception {
  final String message;

  const MobileCodeHelperException(this.message);

  @override
  String toString() => 'MobileCodeHelperException: $message';
}
