import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/services/capability_surface_service.dart';
import 'package:mobile_agent/services/cli_hub_catalog_service.dart';

void main() {
  test('capability surfaces keep runtime, integration, and CLI boundaries', () {
    const service = CapabilitySurfaceService();

    final runtimes = service.runtimeSurfaces();
    expect(runtimes.map((item) => item.id), contains('native-helper'));
    expect(runtimes.map((item) => item.id), contains('alpine-linux-sandbox'));
    expect(runtimes.map((item) => item.id), contains('termux-fallback'));

    final nativeHelper =
        runtimes.singleWhere((item) => item.id == 'native-helper');
    expect(nativeHelper.state, CapabilityState.available);
    expect(nativeHelper.credentialPolicy, CliHubCredentialPolicy.none);
    expect(nativeHelper.boundary.safe, isTrue);
    expect(nativeHelper.mutationTaskKinds, contains('flutter_build_apk'));

    final termux = runtimes.singleWhere((item) => item.id == 'termux-fallback');
    expect(termux.state, CapabilityState.blocked);
    expect(termux.credentialPolicy, CliHubCredentialPolicy.external);
    expect(termux.boundary.termuxDefaultRuntime, isFalse);

    final integrations = service.integrationSurfaces();
    expect(integrations.map((item) => item.id), contains('chatgpt-codex'));
    expect(integrations.map((item) => item.id), contains('github-copilot'));
    for (final item in integrations) {
      expect(item.type, CapabilitySurfaceType.integrationProvider);
      expect(item.boundary.integrationExecutesShell, isFalse);
      expect(item.riskLevel, CliHubRiskLevel.high);
    }
  });

  test('CLI catalog entries become typed extension capabilities', () async {
    const catalogService = CliHubCatalogService();
    const surfaceService = CapabilitySurfaceService();
    final catalog = await catalogService.loadBundledCatalog();

    final github =
        catalog.entries.singleWhere((entry) => entry.id == 'github-cli');
    final capability = surfaceService.cliExtensionSurface(github);

    expect(capability.type, CapabilitySurfaceType.cliExtensionProvider);
    expect(capability.installProfile, 'githubCli');
    expect(capability.probeTaskKind, 'github_cli_probe');
    expect(capability.authTaskKind, 'github_cli_auth_login');
    expect(capability.readOnlyTaskKinds, contains('github_cli_auth_status'));
    expect(capability.mutationTaskKinds, contains('github_cli_auth_login'));
    expect(capability.boundary.cliHubAllowsRawShell, isFalse);
  });
}
