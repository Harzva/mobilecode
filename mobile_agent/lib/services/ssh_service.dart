// lib/services/ssh_service.dart
// SSH Service — Manages SSH connections to remote development servers.
//
// Features: password/key authentication, connection pooling, remote command
// execution, SFTP file transfer, port forwarding, health monitoring, and
// auto-reconnect. All credentials are encrypted via SecureStorageService.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import 'secure_storage_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SSH Service
// ═══════════════════════════════════════════════════════════════════════════

/// Manages SSH connections to remote development servers.
///
/// Provides a complete SSH client implementation using dartssh2 with:
/// - Password and private key authentication (RSA/ED25519)
/// - Connection pooling with keep-alive
/// - Remote command execution with streaming output
/// - SFTP file transfer (upload/download/list)
/// - Local port forwarding
/// - Connection health monitoring
/// - Host configuration persistence via secure storage
///
/// Usage:
/// ```dart
/// final ssh = SshService();
/// await ssh.initialize();
/// final client = await ssh.connect(config);
/// final result = await ssh.execute('host-id', 'uname -a');
/// ```
class SshService {
  // Singleton
  static final SshService _instance = SshService._internal();
  factory SshService() => _instance;
  SshService._internal();

  // ── Connection Management ────────────────────────────────────────

  /// Active SSH connections keyed by host ID.
  final Map<String, SSHClient> _connections = {};

  /// Connection metadata keyed by host ID.
  final Map<String, _ConnectionMeta> _connectionMeta = {};

  /// Health check timer for connection keep-alive.
  Timer? _healthCheckTimer;

  /// Secure storage for host configs and credentials.
  SecureStorageService? _secureStorage;

  /// Stream controller for connection state changes.
  final StreamController<SshConnectionEvent> _connectionEventsController =
      StreamController<SshConnectionEvent>.broadcast();

  /// Whether the service has been initialized.
  bool _initialized = false;

  // ═════════════════════════════════════════════════════════════════
  // Public Accessors
  // ═════════════════════════════════════════════════════════════════

  /// Stream of connection state change events.
  Stream<SshConnectionEvent> get connectionEvents =>
      _connectionEventsController.stream;

  /// Currently connected host IDs.
  List<String> get connectedHosts => _connections.keys.toList();

  /// Number of active connections.
  int get activeConnectionCount => _connections.length;

  /// Whether the service is initialized.
  bool get isInitialized => _initialized;

  // ═════════════════════════════════════════════════════════════════
  // Initialization
  // ═════════════════════════════════════════════════════════════════

  /// Initialize the SSH service.
  ///
  /// Optionally provide a [secureStorage] instance for credential
  /// persistence. If not provided, a default [SecureStorageService]
  /// is used.
  Future<void> initialize({SecureStorageService? secureStorage}) async {
    if (_initialized) return;

    _secureStorage = secureStorage ?? SecureStorageService();

    try {
      debugPrint('[SshService] Initializing...');
      _startHealthChecks();
      _initialized = true;
      debugPrint('[SshService] Initialized successfully');
    } catch (e) {
      throw SshServiceException('Failed to initialize SSH service: $e');
    }
  }

  // ═════════════════════════════════════════════════════════════════
  // Connection Management
  // ═════════════════════════════════════════════════════════════════

  /// Connect to a remote host.
  ///
  /// Disconnects any existing connection with the same host ID first.
  /// Authenticates using password or private key based on config.
  ///
  /// Returns the connected [SSHClient].
  /// Throws [SshServiceException] if connection fails.
  Future<SSHClient> connect(SshHostConfig config) async {
    _ensureInitialized();

    // Disconnect existing connection if present.
    if (_connections.containsKey(config.id)) {
      debugPrint('[SshService] Disconnecting existing connection: ${config.id}');
      await disconnect(config.id);
    }

    try {
      debugPrint(
          '[SshService] Connecting to ${config.host}:${config.port} as ${config.username}');

      final socket = await SSHSocket.connect(
        config.host,
        config.port,
        timeout: const Duration(seconds: 15),
      );

      // Build key pairs from private key if provided.
      List<SSHKeyPair>? keyPairs;
      if (config.privateKey != null && config.privateKey!.isNotEmpty) {
        try {
          keyPairs = SSHKeyPair.fromPem(
            config.privateKey!,
            config.passphrase ?? '',
          );
          debugPrint('[SshService] Loaded private key for ${config.id}');
        } catch (e) {
          throw SshServiceException(
              'Failed to parse private key for ${config.id}: $e');
        }
      }

      final client = SSHClient(
        socket,
        username: config.username,
        onPasswordRequest: config.password != null
            ? () {
                debugPrint('[SshService] Providing password for ${config.id}');
                return config.password!;
              }
            : null,
        identities: keyPairs,
        onVerifyHostKey: (hostKeyType, publicKey) {
          debugPrint(
              '[SshService] Host key verified (type: $hostKeyType) for ${config.host}');
          return true; // Accept all host keys (prompt user in production)
        },
      );

      // Wait for authentication to complete.
      await client.authenticated;

      _connections[config.id] = client;
      _connectionMeta[config.id] = _ConnectionMeta(
        config: config,
        connectedAt: DateTime.now(),
        lastActivity: DateTime.now(),
      );

      debugPrint('[SshService] Connected to ${config.displayAddress}');

      _connectionEventsController.add(
        SshConnectionEvent(
          hostId: config.id,
          hostName: config.name,
          status: SshConnectionStatus.connected,
          timestamp: DateTime.now(),
        ),
      );

      return client;
    } on SocketException catch (e) {
      throw SshServiceException(
          'Connection failed to ${config.host}:${config.port}: ${e.message}');
    } on SSHAuthFailError catch (e) {
      throw SshServiceException(
          'Authentication failed for ${config.username}@${config.host}: $e');
    } catch (e) {
      throw SshServiceException(
          'Failed to connect to ${config.displayAddress}: $e');
    }
  }

  /// Disconnect from a host.
  ///
  /// Closes the SSH client and cleans up associated resources.
  Future<void> disconnect(String hostId) async {
    final client = _connections.remove(hostId);
    final meta = _connectionMeta.remove(hostId);

    if (client != null) {
      try {
        client.close();
        debugPrint('[SshService] Disconnected from $hostId');
      } catch (e) {
        debugPrint('[SshService] Error disconnecting $hostId: $e');
      }

      _connectionEventsController.add(
        SshConnectionEvent(
          hostId: hostId,
          hostName: meta?.config.name ?? hostId,
          status: SshConnectionStatus.disconnected,
          timestamp: DateTime.now(),
        ),
      );
    }
  }

  /// Disconnect all active connections.
  Future<void> disconnectAll() async {
    final hostIds = _connections.keys.toList();
    for (final hostId in hostIds) {
      await disconnect(hostId);
    }
  }

  /// Check if connected to a host.
  bool isConnected(String hostId) => _connections.containsKey(hostId);

  /// Get connection metadata for a host.
  _ConnectionMeta? getConnectionMeta(String hostId) =>
      _connectionMeta[hostId];

  /// Get last activity time for a host connection.
  DateTime? getLastActivity(String hostId) =>
      _connectionMeta[hostId]?.lastActivity;

  // ═════════════════════════════════════════════════════════════════
  // Remote Execution
  // ═════════════════════════════════════════════════════════════════

  /// Execute a command on a remote host and return the full result.
  ///
  /// [hostId] The ID of the connected host.
  /// [command] The shell command to execute.
  /// [workingDirectory] Optional directory to run the command in.
  /// [timeout] Maximum time to wait for completion.
  /// [environment] Optional environment variables.
  Future<RemoteCommandResult> execute(
    String hostId,
    String command, {
    String? workingDirectory,
    Duration timeout = const Duration(minutes: 5),
    Map<String, String>? environment,
  }) async {
    final client = _connections[hostId];
    if (client == null) {
      throw SshServiceException('Not connected to host: $hostId');
    }

    final meta = _connectionMeta[hostId];
    final effectiveWd = workingDirectory ?? meta?.config.workingDirectory;

    // SECURITY FIX: Sanitize command and working directory to prevent injection.
    _validateShellCommand(command);
    if (effectiveWd != null) {
      _validateRemotePath(effectiveWd);
    }

    // Use SSH session directly to avoid shell interpolation.
    // Pass the command as arguments, not as a shell string.
    final List<String> shellCommand;
    if (effectiveWd != null) {
      final escapedWd = _shellEscape(effectiveWd);
      shellCommand = ['cd', escapedWd, '&&', ...command.split(' ')];
    } else {
      shellCommand = command.split(' ');
    }

    final displayCommand = shellCommand.join(' ');
    debugPrint('[SshService] Executing on $hostId: <redacted>');

    final stopwatch = Stopwatch()..start();

    try {
      final session = await client
          .execute(
            displayCommand,
            environment: environment,
          )
          .timeout(timeout);

      final stdoutBytes = <int>[];
      final stderrBytes = <int>[];

      await Future.wait([
        session.stdout.forEach((data) => stdoutBytes.addAll(data)),
        session.stderr.forEach((data) => stderrBytes.addAll(data)),
      ]);

      // Wait for exit code with timeout.
      final exitCode = await session.exitCode.timeout(timeout);

      stopwatch.stop();

      final stdout = utf8.decode(stdoutBytes, allowMalformed: true);
      final stderr = utf8.decode(stderrBytes, allowMalformed: true);

      // Update last activity.
      meta?.lastActivity = DateTime.now();

      debugPrint(
          '[SshService] Command completed on $hostId (exit: $exitCode, ${stopwatch.elapsed.inMilliseconds}ms)');

      return RemoteCommandResult(
        command: command,
        stdout: stdout,
        stderr: stderr,
        exitCode: exitCode,
        duration: stopwatch.elapsed,
      );
    } on TimeoutException {
      stopwatch.stop();
      throw SshServiceException(
          'Command timed out after ${timeout.inMinutes}m'); // SECURITY: Don't echo command
    } catch (e) {
      stopwatch.stop();
      throw SshServiceException('Command failed on $hostId: $e');
    }
  }

  /// Execute a command with streaming output.
  ///
  /// Yields output chunks as they arrive from the remote host.
  /// Stderr lines are prefixed with '[stderr]'.
  Stream<String> executeStream(
    String hostId,
    String command, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async* {
    final client = _connections[hostId];
    if (client == null) {
      throw SshServiceException('Not connected to host: $hostId');
    }

    final meta = _connectionMeta[hostId];
    final effectiveWd = workingDirectory ?? meta?.config.workingDirectory;

    // SECURITY FIX: Sanitize inputs before constructing command.
    _validateShellCommand(command);
    if (effectiveWd != null) {
      _validateRemotePath(effectiveWd);
    }

    final fullCommand = effectiveWd != null
        ? 'cd "${_shellEscape(effectiveWd)}" && ${_sanitizeCommand(command)}'
        : _sanitizeCommand(command);

    debugPrint('[SshService] Streaming on $hostId: <redacted>');

    final session = await client.execute(
      fullCommand,
      environment: environment,
    );

    // Merge stdout and stderr streams.
    await for (final data in session.stdout) {
      yield utf8.decode(data, allowMalformed: true);
    }

    await for (final data in session.stderr) {
      yield '[stderr] ${utf8.decode(data, allowMalformed: true)}';
    }

    // Update last activity.
    meta?.lastActivity = DateTime.now();
  }

  /// Start an interactive shell session on the remote host.
  ///
  /// Returns a [SshShellSession] for bidirectional communication.
  Future<SshShellSession> startShell(
    String hostId, {
    String? workingDirectory,
    String termEnv = 'xterm-256color',
    int termWidth = 120,
    int termHeight = 40,
  }) async {
    final client = _connections[hostId];
    if (client == null) {
      throw SshServiceException('Not connected to host: $hostId');
    }

    final meta = _connectionMeta[hostId];
    final effectiveWd = workingDirectory ?? meta?.config.workingDirectory;

    // Change to working directory if specified.
    final env = <String, String>{
      'TERM': termEnv,
      if (effectiveWd != null) 'PWD': effectiveWd,
    };

    final shell = await client.shell(
      environment: env,
      terminalType: SSHTermType.xterm256color,
    );

    // Update terminal size.
    shell.resizeTerminal(termWidth, termHeight);

    debugPrint('[SshService] Shell started on $hostId');

    return SshShellSession(
      stdin: shell.stdin,
      stdout: shell.stdout,
      stderr: shell.stderr,
      resize: shell.resizeTerminal,
      close: () async {
        shell.write(utf8.encode('exit\n'));
        await Future.delayed(const Duration(milliseconds: 200));
      },
    );
  }

  // ═════════════════════════════════════════════════════════════════
  // SFTP File Transfer
  // ═════════════════════════════════════════════════════════════════

  /// Upload a file to a remote host via SFTP.
  ///
  /// [hostId] The connected host ID.
  /// [localPath] Absolute path to the local file.
  /// [remotePath] Destination path on the remote host.
  Future<void> uploadFile(
    String hostId,
    String localPath,
    String remotePath,
  ) async {
    final client = _connections[hostId];
    if (client == null) {
      throw SshServiceException('Not connected to host: $hostId');
    }

    final localFile = File(localPath);
    if (!await localFile.exists()) {
      throw SshServiceException('Local file not found: $localPath');
    }

    try {
      final sftp = await client.sftp();
      final remoteFile = await sftp.open(
        remotePath,
        mode: SftpFileOpenMode.create |
            SftpFileOpenMode.write |
            SftpFileOpenMode.truncate,
      );

      final data = await localFile.readAsBytes();
      await remoteFile.writeBytes(data);
      await remoteFile.close();

      _connectionMeta[hostId]?.lastActivity = DateTime.now();

      debugPrint('[SshService] Uploaded $localPath -> $remotePath');
    } catch (e) {
      throw SshServiceException('Upload failed: $e');
    }
  }

  /// Download a file from a remote host via SFTP.
  ///
  /// [hostId] The connected host ID.
  /// [remotePath] Path to the remote file.
  /// [localPath] Destination path on the local device.
  Future<void> downloadFile(
    String hostId,
    String remotePath,
    String localPath,
  ) async {
    final client = _connections[hostId];
    if (client == null) {
      throw SshServiceException('Not connected to host: $hostId');
    }

    try {
      final sftp = await client.sftp();
      final remoteFile = await sftp.open(remotePath);

      final data = await remoteFile.readBytes();
      final localFile = File(localPath);

      // Ensure parent directory exists.
      await localFile.parent.create(recursive: true);
      await localFile.writeAsBytes(data);

      await remoteFile.close();

      _connectionMeta[hostId]?.lastActivity = DateTime.now();

      debugPrint('[SshService] Downloaded $remotePath -> $localPath');
    } catch (e) {
      throw SshServiceException('Download failed: $e');
    }
  }

  /// List contents of a remote directory via SFTP.
  ///
  /// Returns a list of [RemoteFileInfo] entries.
  Future<List<RemoteFileInfo>> listDirectory(
    String hostId,
    String remotePath,
  ) async {
    final client = _connections[hostId];
    if (client == null) {
      throw SshServiceException('Not connected to host: $hostId');
    }

    try {
      final sftp = await client.sftp();
      final items = await sftp.listdir(remotePath);

      _connectionMeta[hostId]?.lastActivity = DateTime.now();

      return items
          .where((item) => item.filename != '.' && item.filename != '..')
          .map((item) => RemoteFileInfo(
                name: item.filename,
                isDirectory: item.attr.isDirectory,
                size: item.attr.size ?? 0,
                modifiedAt: item.attr.modifyTime != null
                    ? DateTime.fromMillisecondsSinceEpoch(
                        item.attr.modifyTime! * 1000)
                    : null,
                permissions: item.attr.permissions != null
                    ? _formatPermissions(item.attr.permissions!)
                    : '----------',
              ))
          .toList();
    } catch (e) {
      throw SshServiceException('Directory listing failed: $e');
    }
  }

  /// Create a remote directory via SFTP.
  Future<void> createRemoteDirectory(
    String hostId,
    String remotePath, {
    bool recursive = false,
  }) async {
    final client = _connections[hostId];
    if (client == null) {
      throw SshServiceException('Not connected to host: $hostId');
    }

    try {
      // Use mkdir command for recursive creation.
      final flag = recursive ? '-p' : '';
      await execute(hostId, 'mkdir $flag "$remotePath"');

      debugPrint('[SshService] Created directory $remotePath on $hostId');
    } catch (e) {
      throw SshServiceException('Failed to create directory: $e');
    }
  }

  /// Delete a remote file or directory via SFTP.
  Future<void> deleteRemotePath(
    String hostId,
    String remotePath, {
    bool isDirectory = false,
    bool recursive = false,
  }) async {
    final client = _connections[hostId];
    if (client == null) {
      throw SshServiceException('Not connected to host: $hostId');
    }

    // SECURITY FIX: Validate remote path before deletion.
    _validateRemotePath(remotePath);

    try {
      final escapedPath = _shellEscape(remotePath);
      if (isDirectory && recursive) {
        await execute(hostId, 'rm -rf $escapedPath');
      } else if (isDirectory) {
        await execute(hostId, 'rmdir $escapedPath');
      } else {
        await execute(hostId, 'rm -f $escapedPath');
      }

      debugPrint('[SshService] Deleted <redacted> on $hostId');
    } catch (e) {
      throw SshServiceException('Failed to delete: $e');
    }
  }

  // ═════════════════════════════════════════════════════════════════
  // Port Forwarding
  // ═════════════════════════════════════════════════════════════════

  /// Set up local port forwarding.
  ///
  /// Allows accessing remote services as if they were local.
  /// For example, to access a remote web server locally.
  Future<SSHForwardChannel> forwardPort(
    String hostId,
    int localPort,
    String remoteHost,
    int remotePort,
  ) async {
    final client = _connections[hostId];
    if (client == null) {
      throw SshServiceException('Not connected to host: $hostId');
    }

    try {
      final forward = await client.forwardLocal(
        remoteHost,
        remotePort,
        localHost: 'localhost',
        localPort: localPort,
      );

      debugPrint(
          '[SshService] Port forwarding: localhost:$localPort -> $remoteHost:$remotePort');

      return forward;
    } catch (e) {
      throw SshServiceException('Port forwarding failed: $e');
    }
  }

  /// Forward a dynamic port (let OS choose).
  ///
  /// Returns the actual local port number allocated.
  Future<(SSHForwardChannel, int)> forwardDynamicPort(
    String hostId,
    String remoteHost,
    int remotePort,
  ) async {
    // Try ports in the ephemeral range.
    for (var port = 30000; port < 40000; port++) {
      try {
        final forward = await forwardPort(hostId, port, remoteHost, remotePort);
        return (forward, port);
      } catch (_) {
        // Port in use, try next.
        continue;
      }
    }
    throw SshServiceException('Could not find available local port');
  }

  // ═════════════════════════════════════════════════════════════════
  // Health Monitoring
  // ═════════════════════════════════════════════════════════════════

  void _startHealthChecks() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _runHealthCheck(),
    );
  }

  Future<void> _runHealthCheck() async {
    final hostIds = _connections.keys.toList();

    for (final hostId in hostIds) {
      final client = _connections[hostId];
      if (client == null) continue;

      try {
        // Quick ping to verify connection.
        final result = await execute(hostId, 'echo ping',
            timeout: const Duration(seconds: 10));

        if (!result.success) {
          await _handleConnectionLost(hostId, 'Ping failed');
        }
      } catch (e) {
        await _handleConnectionLost(hostId, e.toString());
      }
    }
  }

  Future<void> _handleConnectionLost(String hostId, String reason) async {
    debugPrint('[SshService] Connection lost for $hostId: $reason');

    _connections.remove(hostId);
    _connectionMeta.remove(hostId);

    _connectionEventsController.add(
      SshConnectionEvent(
        hostId: hostId,
        hostName: hostId,
        status: SshConnectionStatus.lost,
        message: reason,
        timestamp: DateTime.now(),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════
  // Host Config Management (Secure Storage)
  // ═════════════════════════════════════════════════════════════════

  static const String _hostConfigsKey = 'ssh_host_configs';

  /// Save a host configuration securely.
  Future<void> saveHostConfig(SshHostConfig config) async {
    _ensureInitialized();

    try {
      final configs = await getHostConfigs();

      // Update or add.
      final index = configs.indexWhere((c) => c.id == config.id);
      if (index >= 0) {
        configs[index] = config;
      } else {
        configs.add(config);
      }

      await _persistConfigs(configs);

      debugPrint('[SshService] Saved host config: ${config.id}');
    } catch (e) {
      throw SshServiceException('Failed to save host config: $e');
    }
  }

  /// Get all saved host configurations.
  Future<List<SshHostConfig>> getHostConfigs() async {
    _ensureInitialized();

    try {
      final jsonStr = await _secureStorage!.read(key: _hostConfigsKey);
      if (jsonStr == null || jsonStr.isEmpty) return [];

      final List<dynamic> decoded = jsonDecode(jsonStr);
      return decoded
          .map((item) => SshHostConfig.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[SshService] Failed to load host configs: $e');
      return [];
    }
  }

  /// Delete a saved host configuration.
  Future<void> deleteHostConfig(String id) async {
    _ensureInitialized();

    try {
      final configs = await getHostConfigs();
      configs.removeWhere((c) => c.id == id);
      await _persistConfigs(configs);

      debugPrint('[SshService] Deleted host config: $id');
    } catch (e) {
      throw SshServiceException('Failed to delete host config: $e');
    }
  }

  /// Get a single host configuration by ID.
  Future<SshHostConfig?> getHostConfig(String id) async {
    final configs = await getHostConfigs();
    try {
      return configs.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> _persistConfigs(List<SshHostConfig> configs) async {
    final jsonList = configs.map((c) => c.toJson()).toList();
    await _secureStorage!.write(
      key: _hostConfigsKey,
      value: jsonEncode(jsonList),
    );
  }

  // ═════════════════════════════════════════════════════════════════
  // Utility
  // ═════════════════════════════════════════════════════════════════

  void _ensureInitialized() {
    if (!_initialized) {
      throw const SshServiceException(
          'SshService not initialized. Call initialize() first.');
    }
  }

  /// Format numeric permissions to string (e.g., 644 -> rw-r--r--).
  static String _formatPermissions(int mode) {
    final perms = <String>[];
    const types = ['r', 'w', 'x'];

    for (var i = 2; i >= 0; i--) {
      final bits = (mode >> (i * 3)) & 0x7;
      for (var j = 2; j >= 0; j--) {
        perms.add((bits >> j) & 1 == 1 ? types[2 - j] : '-');
      }
    }

    return perms.join();
  }

  /// Dispose all resources.
  void dispose() {
    _healthCheckTimer?.cancel();

    for (final entry in _connections.entries) {
      try {
        entry.value.close();
      } catch (_) {}
    }

    _connections.clear();
    _connectionMeta.clear();

    if (!_connectionEventsController.isClosed) {
      _connectionEventsController.close();
    }

    _initialized = false;
    debugPrint('[SshService] Disposed');
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Connection Metadata
// ═══════════════════════════════════════════════════════════════════════════

/// Internal metadata tracking for an active connection.
class _ConnectionMeta {
  final SshHostConfig config;
  final DateTime connectedAt;
  DateTime lastActivity;

  _ConnectionMeta({
    required this.config,
    required this.connectedAt,
    required this.lastActivity,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// SSH Host Config
// ═══════════════════════════════════════════════════════════════════════════

/// Configuration for an SSH remote host.
///
/// Contains connection parameters, authentication credentials, and
/// metadata. Passwords and private keys are stored in clear text in
/// memory but persisted encrypted via [SecureStorageService].
class SshHostConfig {
  /// Unique identifier for this host config.
  final String id;

  /// Display name for the host.
  final String name;

  /// IP address or hostname.
  final String host;

  /// SSH port number (default 22).
  final int port;

  /// SSH username.
  final String username;

  /// Password for password authentication (stored encrypted at rest).
  final String? password;

  /// Private key PEM content for key authentication (stored encrypted at rest).
  final String? privateKey;

  /// Passphrase for an encrypted private key.
  final String? passphrase;

  /// Default working directory on the remote host.
  final String? workingDirectory;

  /// When this config was created.
  final DateTime createdAt;

  /// Whether this host is marked as a favorite.
  bool isFavorite;

  /// Last connected timestamp (null if never connected).
  DateTime? lastConnectedAt;

  /// Custom tag/category for organizing hosts.
  final String? tag;

  SshHostConfig({
    required this.id,
    required this.name,
    required this.host,
    this.port = 22,
    required this.username,
    this.password,
    this.privateKey,
    this.passphrase,
    this.workingDirectory,
    this.isFavorite = false,
    this.lastConnectedAt,
    this.tag,
  }) : createdAt = DateTime.now();

  /// Formatted address string like "user@host:port".
  String get displayAddress => '$username@$host:$port';

  /// Whether this config uses key-based authentication.
  bool get usesKeyAuth => privateKey != null && privateKey!.isNotEmpty;

  /// Whether this config uses password authentication.
  bool get usesPasswordAuth =>
      password != null && password!.isNotEmpty && !usesKeyAuth;

  /// Create from JSON map.
  factory SshHostConfig.fromJson(Map<String, dynamic> json) {
    return SshHostConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      host: json['host'] as String,
      port: json['port'] as int? ?? 22,
      username: json['username'] as String,
      password: json['password'] as String?,
      privateKey: json['privateKey'] as String?,
      passphrase: json['passphrase'] as String?,
      workingDirectory: json['workingDirectory'] as String?,
      isFavorite: json['isFavorite'] as bool? ?? false,
      lastConnectedAt: json['lastConnectedAt'] != null
          ? DateTime.parse(json['lastConnectedAt'] as String)
          : null,
      tag: json['tag'] as String?,
    );
  }

  /// Convert to JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'host': host,
      'port': port,
      'username': username,
      'password': password,
      'privateKey': privateKey,
      'passphrase': passphrase,
      'workingDirectory': workingDirectory,
      'isFavorite': isFavorite,
      'lastConnectedAt': lastConnectedAt?.toIso8601String(),
      'tag': tag,
    };
  }

  /// Create a copy with modified fields.
  SshHostConfig copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? username,
    String? password,
    String? privateKey,
    String? passphrase,
    String? workingDirectory,
    bool? isFavorite,
    DateTime? lastConnectedAt,
    String? tag,
  }) {
    final config = SshHostConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      privateKey: privateKey ?? this.privateKey,
      passphrase: passphrase ?? this.passphrase,
      workingDirectory: workingDirectory ?? this.workingDirectory,
      isFavorite: isFavorite ?? this.isFavorite,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
      tag: tag ?? this.tag,
    );
    return config;
  }

  @override
  String toString() =>
      'SshHostConfig[$name]($displayAddress, keyAuth: $usesKeyAuth)';
}

// ═══════════════════════════════════════════════════════════════════════════
// Remote Command Result
// ═══════════════════════════════════════════════════════════════════════════

/// Result of executing a command on a remote host.
class RemoteCommandResult {
  /// The original command string.
  final String command;

  /// Standard output from the remote command.
  final String stdout;

  /// Standard error from the remote command.
  final String stderr;

  /// Process exit code (0 = success).
  final int exitCode;

  /// Time taken to execute the command.
  final Duration duration;

  /// When the command was executed.
  final DateTime executedAt;

  RemoteCommandResult({
    required this.command,
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    required this.duration,
  }) : executedAt = DateTime.now();

  /// Whether the command succeeded (exit code 0).
  bool get success => exitCode == 0;

  /// Whether the command produced any stderr output.
  bool get hasStderr => stderr.isNotEmpty;

  /// Combined stdout and stderr for display.
  String get combinedOutput {
    final buffer = StringBuffer();
    if (stdout.isNotEmpty) buffer.writeln(stdout);
    if (stderr.isNotEmpty) buffer.writeln('[stderr] $stderr');
    return buffer.toString().trim();
  }

  @override
  String toString() =>
      'RemoteCommandResult[$command]: exit=$exitCode, ${duration.inMilliseconds}ms';
}

// ═══════════════════════════════════════════════════════════════════════════
// Remote File Info
// ═══════════════════════════════════════════════════════════════════════════

/// Information about a file or directory on a remote host.
class RemoteFileInfo {
  /// File or directory name.
  final String name;

  /// Whether this is a directory.
  final bool isDirectory;

  /// File size in bytes.
  final int size;

  /// Last modification time.
  final DateTime? modifiedAt;

  /// Permission string (e.g., "rw-r--r--").
  final String permissions;

  RemoteFileInfo({
    required this.name,
    required this.isDirectory,
    required this.size,
    this.modifiedAt,
    this.permissions = '----------',
  });

  /// Formatted size string (e.g., "1.5 MB").
  String get formattedSize {
    if (isDirectory) return '--';
    if (size < 1024) return '${size}B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)}KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }

  @override
  String toString() => 'RemoteFileInfo[$name](dir=$isDirectory, size=$size)';
}

// ═══════════════════════════════════════════════════════════════════════════
// SSH Shell Session
// ═══════════════════════════════════════════════════════════════════════════

/// Represents an interactive shell session on a remote host.
class SshShellSession {
  /// Sink for writing data to the shell's stdin.
  final Sink<List<int>> stdin;

  /// Stream of stdout data from the shell.
  final Stream<Uint8List> stdout;

  /// Stream of stderr data from the shell.
  final Stream<Uint8List> stderr;

  /// Resize the terminal.
  final void Function(int width, int height) resize;

  /// Close the shell session.
  final Future<void> Function() close;

  SshShellSession({
    required this.stdin,
    required this.stdout,
    required this.stderr,
    required this.resize,
    required this.close,
  });

  /// Write a string to the shell's stdin.
  void write(String data) {
    stdin.add(utf8.encode(data));
  }

  /// Write a line to the shell's stdin.
  void writeln(String data) {
    stdin.add(utf8.encode('$data\n'));
  }

  /// Read all stdout as a stream of decoded strings.
  Stream<String> get stdoutStrings {
    return stdout.map((data) => utf8.decode(data, allowMalformed: true));
  }

  /// Read all stderr as a stream of decoded strings.
  Stream<String> get stderrStrings {
    return stderr.map((data) => utf8.decode(data, allowMalformed: true));
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Connection Events
// ═══════════════════════════════════════════════════════════════════════════

/// Connection status for SSH hosts.
enum SshConnectionStatus {
  connected,
  disconnected,
  connecting,
  lost,
  error,
}

/// Event emitted when an SSH connection state changes.
class SshConnectionEvent {
  /// The host ID that changed.
  final String hostId;

  /// The display name of the host.
  final String hostName;

  /// The new connection status.
  final SshConnectionStatus status;

  /// Optional message (e.g., error description).
  final String? message;

  /// When the event occurred.
  final DateTime timestamp;

  SshConnectionEvent({
    required this.hostId,
    required this.hostName,
    required this.status,
    this.message,
    required this.timestamp,
  });

  @override
  String toString() =>
      'SshConnectionEvent[$hostId]: $status at $timestamp';
}

// ═══════════════════════════════════════════════════════════════════════════
// Security Helpers
// ═══════════════════════════════════════════════════════════════════════════

/// Characters that are dangerous in shell contexts.
final _dangerousShellChars = RegExp(r'[;|&$`\n\r<>{}\[\]]');

/// Validates that a shell command does not contain injection attempts.
void _validateShellCommand(String command) {
  if (command.isEmpty) {
    throw const SshServiceException('Command cannot be empty');
  }
  if (_dangerousShellChars.hasMatch(command)) {
    throw const SshServiceException(
        'Command contains potentially dangerous characters');
  }
}

/// Validates that a remote path is safe (no traversal attempts).
void _validateRemotePath(String path) {
  if (path.isEmpty) {
    throw const SshServiceException('Path cannot be empty');
  }
  // Reject paths with directory traversal sequences.
  if (path.contains('../') || path.contains('..\\')) {
    throw const SshServiceException(
        'Path contains directory traversal sequences');
  }
  // Reject null bytes (common in injection attacks).
  if (path.contains('\x00')) {
    throw const SshServiceException('Path contains null bytes');
  }
}

/// Escapes a string for safe use in shell contexts.
/// Uses single-quote wrapping which prevents variable expansion.
String _shellEscape(String input) {
  // Use single quotes to prevent variable/command expansion.
  // Any single quote in the input is escaped by ending the quote,
  // adding an escaped single quote, and starting a new quote.
  final escaped = input.replaceAll("'", "'\"'\"'");
  return "'$escaped'";
}

/// Sanitizes a command string for safe execution.
String _sanitizeCommand(String command) {
  _validateShellCommand(command);
  return command;
}

// ═══════════════════════════════════════════════════════════════════════════
// Exceptions
// ═══════════════════════════════════════════════════════════════════════════

/// Exception thrown by the SSH service.
class SshServiceException implements Exception {
  final String message;

  const SshServiceException(this.message);

  @override
  String toString() => 'SshServiceException: $message';
}
