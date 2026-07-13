import 'cli_hub_catalog_service.dart';
import 'harness_permission_service.dart';

enum CliHarnessTaskAccess { readOnly, mutation, rawShell }

class CliHarnessTaskDescriptor {
  const CliHarnessTaskDescriptor({
    required this.id,
    required this.cliId,
    required this.title,
    required this.taskKind,
    required this.access,
    required this.requiresApproval,
    required this.riskLevel,
    required this.credentialPolicy,
    required this.payload,
    this.requiresSecondApproval = false,
    this.previewCommand,
    this.blockedReason,
  });

  final String id;
  final String cliId;
  final String title;
  final String taskKind;
  final CliHarnessTaskAccess access;
  final bool requiresApproval;
  final bool requiresSecondApproval;
  final CliHubRiskLevel riskLevel;
  final CliHubCredentialPolicy credentialPolicy;
  final Map<String, dynamic> payload;
  final String? previewCommand;
  final String? blockedReason;

  bool get canRunWithoutApproval =>
      access == CliHarnessTaskAccess.readOnly &&
      !requiresApproval &&
      riskLevel == CliHubRiskLevel.low;
}

class CliHarnessCapabilityService {
  const CliHarnessCapabilityService();

  List<CliHarnessTaskDescriptor> descriptorsForCatalog(
    CliHubCatalog catalog, {
    required bool allowHarnessCliTasks,
    HarnessPermissionMode permissionMode =
        HarnessPermissionMode.approveSafeTypedTasks,
  }) {
    if (!allowHarnessCliTasks) return const [];
    final descriptors = <CliHarnessTaskDescriptor>[];
    if (const HarnessPermissionService().allowsRawShell(permissionMode)) {
      descriptors.add(
        const CliHarnessTaskDescriptor(
          id: 'raw-shell.request',
          cliId: 'raw-shell',
          title: 'Raw Shell / 用户授权命令',
          taskKind: 'raw_shell',
          access: CliHarnessTaskAccess.rawShell,
          requiresApproval: true,
          riskLevel: CliHubRiskLevel.high,
          credentialPolicy: CliHubCredentialPolicy.forbidden,
          payload: {},
          previewCommand: '<user provided command>',
        ),
      );
    }
    for (final entry in catalog.entries) {
      final probeTaskKind = entry.probe.taskKind;
      if (probeTaskKind != null) {
        descriptors.add(
          CliHarnessTaskDescriptor(
            id: '${entry.id}.probe',
            cliId: entry.id,
            title: '${entry.title} / 检测',
            taskKind: probeTaskKind,
            access: CliHarnessTaskAccess.readOnly,
            requiresApproval: false,
            riskLevel: CliHubRiskLevel.low,
            credentialPolicy: entry.credentialPolicy,
            payload: const {},
          ),
        );
      }
      for (final task in entry.tasks) {
        descriptors.add(CliHarnessTaskDescriptor(
          id: '${entry.id}.${task.id}',
          cliId: entry.id,
          title: '${entry.title} / ${task.label}',
          taskKind: task.taskKind,
          access: entry.mutationTaskIds.contains(task.id)
              ? CliHarnessTaskAccess.mutation
              : CliHarnessTaskAccess.readOnly,
          requiresApproval: task.requiresApproval ||
              entry.mutationTaskIds.contains(task.id) ||
              entry.credentialPolicy != CliHubCredentialPolicy.none,
          riskLevel: entry.riskLevel,
          credentialPolicy: entry.credentialPolicy,
          payload: Map<String, dynamic>.unmodifiable(task.payload),
        ));
      }
    }
    return List.unmodifiable(descriptors);
  }

  CliHarnessTaskDescriptor rawShellPreview({
    required String command,
    required HarnessPermissionMode permissionMode,
  }) {
    final risk = const HarnessPermissionService().classifyRawShellCommand(
      command,
      mode: permissionMode,
    );
    return CliHarnessTaskDescriptor(
      id: 'raw-shell.preview',
      cliId: 'raw-shell',
      title: 'Raw Shell / Preview',
      taskKind: 'raw_shell',
      access: CliHarnessTaskAccess.rawShell,
      requiresApproval: risk.requiresApproval,
      requiresSecondApproval: risk.requiresSecondApproval,
      riskLevel: risk.requiresSecondApproval
          ? CliHubRiskLevel.high
          : CliHubRiskLevel.medium,
      credentialPolicy: CliHubCredentialPolicy.forbidden,
      payload: {
        'command': command,
        'permissionMode': permissionMode.name,
        'riskReason': risk.reason,
      },
      previewCommand: command,
      blockedReason:
          risk.reason == 'raw_shell_requires_full_access' ? risk.reason : null,
    );
  }
}
