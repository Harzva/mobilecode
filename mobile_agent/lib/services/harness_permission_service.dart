import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum HarnessPermissionMode {
  askEveryTime,
  approveSafeTypedTasks,
  fullAccess,
}

extension HarnessPermissionModeLabels on HarnessPermissionMode {
  String get label => switch (this) {
        HarnessPermissionMode.askEveryTime => 'Ask every time',
        HarnessPermissionMode.approveSafeTypedTasks =>
          'Approve safe typed tasks',
        HarnessPermissionMode.fullAccess => 'Full access',
      };

  String get shortLabel => switch (this) {
        HarnessPermissionMode.askEveryTime => 'Ask',
        HarnessPermissionMode.approveSafeTypedTasks => 'Typed',
        HarnessPermissionMode.fullAccess => 'Full',
      };

  String get description => switch (this) {
        HarnessPermissionMode.askEveryTime => '每个 harness action 都需要用户确认。',
        HarnessPermissionMode.approveSafeTypedTasks =>
          '安全 typed task 可自动批准，raw shell 不暴露给模型。',
        HarnessPermissionMode.fullAccess =>
          '模型可请求 raw_shell preview；危险命令仍需要二次确认。',
      };

  String get storageValue => name;

  static HarnessPermissionMode fromStorageValue(String? value) {
    return HarnessPermissionMode.values.firstWhere(
      (mode) => mode.storageValue == value,
      orElse: () => HarnessPermissionMode.approveSafeTypedTasks,
    );
  }
}

class HarnessPermissionStore extends ChangeNotifier {
  HarnessPermissionStore._();

  static final HarnessPermissionStore instance = HarnessPermissionStore._();
  static const String storageKey = 'mobilecode.harness.permissionMode';

  HarnessPermissionMode _mode = HarnessPermissionMode.approveSafeTypedTasks;
  bool _loaded = false;

  HarnessPermissionMode get mode => _mode;
  bool get loaded => _loaded;

  Future<HarnessPermissionMode> load() async {
    final prefs = await SharedPreferences.getInstance();
    final nextMode = HarnessPermissionModeLabels.fromStorageValue(
        prefs.getString(storageKey));
    _loaded = true;
    if (nextMode != _mode) {
      _mode = nextMode;
      notifyListeners();
    }
    return _mode;
  }

  Future<void> setMode(HarnessPermissionMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, mode.storageValue);
    if (_mode == mode && _loaded) return;
    _mode = mode;
    _loaded = true;
    notifyListeners();
  }
}

class HarnessCommandRisk {
  const HarnessCommandRisk({
    required this.requiresApproval,
    required this.requiresSecondApproval,
    required this.reason,
  });

  final bool requiresApproval;
  final bool requiresSecondApproval;
  final String reason;
}

class HarnessPermissionService {
  const HarnessPermissionService();

  bool allowsRawShell(HarnessPermissionMode mode) {
    return mode == HarnessPermissionMode.fullAccess;
  }

  HarnessCommandRisk classifyRawShellCommand(
    String command, {
    required HarnessPermissionMode mode,
  }) {
    final normalized = _normalize(command);
    if (!allowsRawShell(mode)) {
      return const HarnessCommandRisk(
        requiresApproval: true,
        requiresSecondApproval: false,
        reason: 'raw_shell_requires_full_access',
      );
    }
    if (_isDestructive(normalized)) {
      return const HarnessCommandRisk(
        requiresApproval: true,
        requiresSecondApproval: true,
        reason: 'destructive_shell_command',
      );
    }
    if (_isNetworkInstaller(normalized)) {
      return const HarnessCommandRisk(
        requiresApproval: true,
        requiresSecondApproval: true,
        reason: 'network_installer_shell_command',
      );
    }
    if (_isCredentialProbe(normalized)) {
      return const HarnessCommandRisk(
        requiresApproval: true,
        requiresSecondApproval: true,
        reason: 'credential_probe_shell_command',
      );
    }
    return const HarnessCommandRisk(
      requiresApproval: true,
      requiresSecondApproval: false,
      reason: 'raw_shell_full_access',
    );
  }
}

String _normalize(String command) {
  return command.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
}

bool _isDestructive(String command) {
  final destructive = [
    RegExp(r'(^|[;&|]\s*)rm\s+[^;&|]*-[a-z]*r[a-z]*f?'),
    RegExp(r'(^|[;&|]\s*)rm\s+[^;&|]*-[a-z]*f[a-z]*r'),
    RegExp(r'(^|[;&|]\s*)find\s+.+\s+-delete(\s|$)'),
    RegExp(r'(^|[;&|]\s*)git\s+clean\s+[^;&|]*-[a-z]*f'),
    RegExp(r'(^|[;&|]\s*)dd\s+'),
    RegExp(r'(^|[;&|]\s*)mkfs(\.| |$)'),
    RegExp(r'>\s*(/|~|\.\.)'),
  ];
  return destructive.any((pattern) => pattern.hasMatch(command));
}

bool _isNetworkInstaller(String command) {
  return RegExp(r'(curl|wget|fetch)\s+.+\|\s*(sh|bash|zsh|python|node)')
          .hasMatch(command) ||
      RegExp(r'(npm|pnpm|yarn)\s+.*(install|add)\s+.*(-g|--global)')
          .hasMatch(command);
}

bool _isCredentialProbe(String command) {
  final probes = [
    'gh auth token',
    'cat ~/.config/gh/hosts.yml',
    'printenv',
    'env',
    '.env',
    'cookie',
    'token',
    'secret',
  ];
  return probes.any(command.contains);
}
