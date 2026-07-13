import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/services/cli_hub_runtime_events.dart';

void main() {
  test('publishes install and auth state changes for UI refresh listeners',
      () async {
    final events = <CliHubRuntimeEvent>[];
    final subscription = CliHubRuntimeEvents.stream.listen(events.add);
    addTearDown(subscription.cancel);

    CliHubRuntimeEvents.publish(const CliHubRuntimeEvent(
      cliId: 'github-cli',
      taskKind: 'package_install',
      status: 'completed',
      success: true,
      profileId: 'githubCli',
    ));

    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(1));
    expect(events.single.cliId, 'github-cli');
    expect(events.single.profileId, 'githubCli');
    expect(events.single.changesInstallOrAuthState, true);
  });
}
