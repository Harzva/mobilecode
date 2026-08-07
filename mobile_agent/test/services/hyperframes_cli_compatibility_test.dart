import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/services/cli_hub_catalog_service.dart';
import 'package:mobile_agent/services/linux_sandbox_provider.dart';

void main() {
  test('bundled CLI catalog exposes the supported HyperFrames task slice',
      () async {
    final catalog = await const CliHubCatalogService().loadBundledCatalog();
    final entry = catalog.entries.singleWhere(
      (item) => item.id == 'hyperframes-cli',
    );

    expect(entry.install.profileId, 'hyperframesCli');
    expect(entry.probe.taskKind, 'hyperframes_cli_probe');
    expect(
      entry.tasks.map((task) => task.taskKind),
      containsAll(<String>[
        'hyperframes_lint',
        'hyperframes_check',
        'hyperframes_compositions',
        'hyperframes_render',
      ]),
    );
    expect(entry.readOnlyTaskIds, hasLength(3));
    expect(entry.mutationTaskIds, ['hyperframes-render']);
  });

  test('Linux Sandbox blocks HyperFrames render until approval', () async {
    final provider = LinuxSandboxRuntimeProvider();

    final result = await provider.runTypedTask(
      taskKind: 'hyperframes_render',
      payload: const {'output': 'movie.mp4'},
    );

    expect(result['success'], isFalse);
    expect(result['failureKind'], 'approvalRequired');
    expect(result['stderr'], contains('explicit user approval'));
  });

  test('Linux Sandbox rejects unknown HyperFrames task kinds', () async {
    final provider = LinuxSandboxRuntimeProvider();

    final result = await provider.runTypedTask(
      taskKind: 'hyperframes_shell',
      payload: const {'command': 'hyperframes render .'},
    );

    expect(result['success'], isFalse);
    expect(result['failureKind'], 'commandBlocked');
  });
}
