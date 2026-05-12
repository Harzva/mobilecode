// lib/providers/ssh_provider.dart
// SSH Provider — Riverpod state management for SSH connections.
//
// Manages SSH host configurations, connection states, terminal output
// for remote hosts, and exposes the SshService to the UI.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/ssh_service.dart';
import '../services/secure_storage_service.dart';
import 'terminal_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Providers
// ═══════════════════════════════════════════════════════════════════════════

/// The SSH service instance (singleton).
///
/// Initialized with secure storage on first access.
final sshServiceProvider = Provider<SshService>((ref) {
  final service = SshService();
  service.initialize();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Secure storage service for SSH credentials.
final _sshSecureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

/// Main SSH notifier that manages hosts and connections.
///
/// Access via:
/// ```dart
/// final ssh = ref.read(sshProvider.notifier);
/// await ssh.connect(hostConfig);
/// ```
final sshProvider = StateNotifierProvider<SshNotifier, SshState>((ref) {
  final service = ref.watch(sshServiceProvider);
  return SshNotifier(service, ref);
});

/// Provider for the list of saved SSH host configurations.
final sshHostsProvider = FutureProvider<List<SshHostConfig>>((ref) async {
  final service = ref.watch(sshServiceProvider);
  return service.getHostConfigs();
});

/// Provider for connection states of all hosts (hostId -> status).
final sshConnectionStatesProvider =
    Provider<Map<String, SshConnectionStatus>>((ref) {
  final state = ref.watch(sshProvider);
  return state.connectionStates;
});

/// Provider for a specific host's connection state.
final sshConnectionStateProvider =
    Provider.family<SshConnectionStatus, String>((ref, hostId) {
  final states = ref.watch(sshConnectionStatesProvider);
  return states[hostId] ?? SshConnectionStatus.disconnected;
});

/// Provider for whether a specific host is connected.
final isHostConnectedProvider = Provider.family<bool, String>((ref, hostId) {
  final state = ref.watch(sshConnectionStateProvider(hostId));
  return state == SshConnectionStatus.connected;
});

/// Provider for terminal output lines of a specific host.
///
/// Each connected host has its own output buffer.
final sshTerminalOutputProvider = StateNotifierProvider.family<
    SshTerminalOutputNotifier, List<TerminalLine>, String>((ref, hostId) {
  return SshTerminalOutputNotifier();
});

// ═══════════════════════════════════════════════════════════════════════════
// SSH State
// ═══════════════════════════════════════════════════════════════════════════

/// Immutable state for the SSH provider.
@immutable
class SshState {
  /// Map of host ID to connection status.
  final Map<String, SshConnectionStatus> connectionStates;

  /// Currently executing host ID (null if idle).
  final String? executingHostId;

  /// Last error message, if any.
  final String? lastError;

  /// Whether a connection operation is in progress.
  final bool isLoading;

  const SshState({
    this.connectionStates = const {},
    this.executingHostId,
    this.lastError,
    this.isLoading = false,
  });

  SshState copyWith({
    Map<String, SshConnectionStatus>? connectionStates,
    String? executingHostId,
    String? lastError,
    bool? isLoading,
  }) {
    return SshState(
      connectionStates: connectionStates ?? this.connectionStates,
      executingHostId: executingHostId ?? this.executingHostId,
      lastError: lastError ?? this.lastError,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  /// Get a list of currently connected host IDs.
  List<String> get connectedHostIds => connectionStates.entries
      .where((e) => e.value == SshConnectionStatus.connected)
      .map((e) => e.key)
      .toList();

  /// Whether any host is currently connected.
  bool get hasActiveConnections =>
      connectionStates.values.any((s) => s == SshConnectionStatus.connected);
}

// ═══════════════════════════════════════════════════════════════════════════
// SSH Notifier
// ═══════════════════════════════════════════════════════════════════════════

/// State notifier that manages SSH connections and host configurations.
///
/// Bridges the [SshService] with the UI, handling connection lifecycle,
/// command execution, and host configuration CRUD.
class SshNotifier extends StateNotifier<SshState> {
  final SshService _service;
  final Ref _ref;
  StreamSubscription<SshConnectionEvent>? _connectionEventsSub;

  SshNotifier(this._service, this._ref) : super(const SshState()) {
    _listenToConnectionEvents();
  }

  /// Subscribe to connection events from the service.
  void _listenToConnectionEvents() {
    _connectionEventsSub = _service.connectionEvents.listen((event) {
      final newStates = Map<String, SshConnectionStatus>.from(
        state.connectionStates,
      );

      switch (event.status) {
        case SshConnectionStatus.connected:
          newStates[event.hostId] = SshConnectionStatus.connected;
          break;
        case SshConnectionStatus.disconnected:
        case SshConnectionStatus.lost:
          newStates[event.hostId] = SshConnectionStatus.disconnected;
          break;
        case SshConnectionStatus.connecting:
          newStates[event.hostId] = SshConnectionStatus.connecting;
          break;
        case SshConnectionStatus.error:
          newStates[event.hostId] = SshConnectionStatus.error;
          break;
      }

      state = state.copyWith(
        connectionStates: newStates,
        lastError: event.status == SshConnectionStatus.error
            ? event.message
            : state.lastError,
      );
    });
  }

  // ── Connection Management ────────────────────────────────────────

  /// Connect to a remote host.
  Future<void> connect(SshHostConfig host) async {
    _setConnectionState(host.id, SshConnectionStatus.connecting);

    try {
      await _service.connect(host);

      // Update last connected time.
      final updated = host.copyWith(lastConnectedAt: DateTime.now());
      await _service.saveHostConfig(updated);

      // Refresh hosts list.
      _ref.invalidate(sshHostsProvider);
    } catch (e) {
      _setConnectionState(host.id, SshConnectionStatus.error);
      state = state.copyWith(lastError: e.toString());
      rethrow;
    }
  }

  /// Disconnect from a host.
  Future<void> disconnect(String hostId) async {
    await _service.disconnect(hostId);
    _setConnectionState(hostId, SshConnectionStatus.disconnected);
  }

  /// Disconnect all active connections.
  Future<void> disconnectAll() async {
    await _service.disconnectAll();
    state = SshState(
      connectionStates: state.connectionStates.map(
        (k, v) => MapEntry(k, SshConnectionStatus.disconnected),
      ),
    );
  }

  void _setConnectionState(String hostId, SshConnectionStatus status) {
    final newStates = Map<String, SshConnectionStatus>.from(
      state.connectionStates,
    );
    newStates[hostId] = status;
    state = state.copyWith(connectionStates: newStates);
  }

  // ── Remote Execution ─────────────────────────────────────────────

  /// Execute a command on a connected host.
  Future<RemoteCommandResult> executeOnHost(
    String hostId,
    String command, {
    String? workingDirectory,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    state = state.copyWith(executingHostId: hostId);

    try {
      final result = await _service.execute(
        hostId,
        command,
        workingDirectory: workingDirectory,
        timeout: timeout,
      );
      return result;
    } finally {
      state = state.copyWith(executingHostId: null);
    }
  }

  /// Execute a command and stream output.
  Stream<String> executeStream(
    String hostId,
    String command, {
    String? workingDirectory,
  }) {
    return _service.executeStream(
      hostId,
      command,
      workingDirectory: workingDirectory,
    );
  }

  // ── SFTP File Operations ─────────────────────────────────────────

  /// Upload a file to a remote host.
  Future<void> uploadFile(
    String hostId,
    String localPath,
    String remotePath,
  ) async {
    await _service.uploadFile(hostId, localPath, remotePath);
  }

  /// Download a file from a remote host.
  Future<void> downloadFile(
    String hostId,
    String remotePath,
    String localPath,
  ) async {
    await _service.downloadFile(hostId, remotePath, localPath);
  }

  /// List a remote directory.
  Future<List<RemoteFileInfo>> listDirectory(
    String hostId,
    String remotePath,
  ) async {
    return _service.listDirectory(hostId, remotePath);
  }

  /// Create a remote directory.
  Future<void> createDirectory(
    String hostId,
    String remotePath, {
    bool recursive = false,
  }) async {
    await _service.createRemoteDirectory(
      hostId,
      remotePath,
      recursive: recursive,
    );
  }

  /// Delete a remote file or directory.
  Future<void> deleteRemotePath(
    String hostId,
    String remotePath, {
    bool isDirectory = false,
    bool recursive = false,
  }) async {
    await _service.deleteRemotePath(
      hostId,
      remotePath,
      isDirectory: isDirectory,
      recursive: recursive,
    );
  }

  // ── Port Forwarding ──────────────────────────────────────────────

  /// Set up local port forwarding.
  Future<SSHForwardChannel> forwardPort(
    String hostId,
    int localPort,
    String remoteHost,
    int remotePort,
  ) async {
    return _service.forwardPort(hostId, localPort, remoteHost, remotePort);
  }

  // ── Host Config CRUD ─────────────────────────────────────────────

  /// Save a host configuration.
  Future<void> saveHost(SshHostConfig config) async {
    await _service.saveHostConfig(config);
    _ref.invalidate(sshHostsProvider);
  }

  /// Delete a host configuration.
  Future<void> deleteHost(String hostId) async {
    // Disconnect first if connected.
    if (state.connectionStates[hostId] == SshConnectionStatus.connected) {
      await disconnect(hostId);
    }
    await _service.deleteHostConfig(hostId);
    _ref.invalidate(sshHostsProvider);
  }

  /// Get a host configuration by ID.
  Future<SshHostConfig?> getHostConfig(String id) async {
    return _service.getHostConfig(id);
  }

  /// Toggle favorite status for a host.
  Future<void> toggleFavorite(String hostId) async {
    final configs = await _service.getHostConfigs();
    final config = configs.firstWhere(
      (c) => c.id == hostId,
      orElse: () => throw SshServiceException('Host not found: $hostId'),
    );
    final updated = config.copyWith(isFavorite: !config.isFavorite);
    await saveHost(updated);
  }

  // ── Utility ──────────────────────────────────────────────────────

  /// Clear the last error.
  void clearError() {
    state = state.copyWith(lastError: null);
  }

  /// Check if a command is executing on any host.
  bool get isExecuting => state.executingHostId != null;

  @override
  void dispose() {
    _connectionEventsSub?.cancel();
    super.dispose();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SSH Terminal Output Notifier
// ═══════════════════════════════════════════════════════════════════════════

/// Manages terminal output lines for a specific SSH host.
///
/// Each host has its own output buffer, keyed by host ID.
class SshTerminalOutputNotifier extends StateNotifier<List<TerminalLine>> {
  SshTerminalOutputNotifier() : super([]);

  /// Add a line to the output buffer.
  void addLine(TerminalLine line) {
    final newLines = [...state, line];
    // Cap at 5000 lines to prevent memory issues.
    if (newLines.length > 5000) {
      newLines.removeAt(0);
    }
    state = newLines;
  }

  /// Add a system message to the output.
  void addSystemMessage(String message) {
    addLine(TerminalLine.system(message));
  }

  /// Add an error message to the output.
  void addError(String message) {
    addLine(TerminalLine.error(message));
  }

  /// Add command output as multiple lines.
  void addOutput(String output) {
    const splitter = LineSplitter();
    for (final line in splitter.convert(output)) {
      if (line.isNotEmpty) {
        addLine(TerminalLine.normal(line));
      }
    }
  }

  /// Clear all output lines.
  void clear() {
    state = [];
  }
}
