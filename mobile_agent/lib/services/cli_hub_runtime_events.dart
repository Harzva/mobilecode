import 'dart:async';

class CliHubRuntimeEvent {
  const CliHubRuntimeEvent({
    required this.cliId,
    required this.taskKind,
    required this.status,
    required this.success,
    this.profileId,
  });

  final String cliId;
  final String taskKind;
  final String status;
  final bool success;
  final String? profileId;

  bool get changesInstallOrAuthState =>
      taskKind == 'package_install' ||
      taskKind.contains('_auth_') ||
      taskKind.endsWith('_auth_status') ||
      taskKind.endsWith('_me');
}

class CliHubRuntimeEvents {
  CliHubRuntimeEvents._();

  static final StreamController<CliHubRuntimeEvent> _controller =
      StreamController<CliHubRuntimeEvent>.broadcast();

  static Stream<CliHubRuntimeEvent> get stream => _controller.stream;

  static void publish(CliHubRuntimeEvent event) {
    if (!_controller.isClosed) _controller.add(event);
  }
}
