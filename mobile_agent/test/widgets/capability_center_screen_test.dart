import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/screens/capability_center_screen.dart';
import 'package:mobile_agent/services/linux_sandbox_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('mobilecode/system_tools');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('capability center exposes the four normalized pages',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getPhoneUseAccessibilityStatus':
          return const {
            'supported': true,
            'accessibilityEnabled': false,
            'serviceConnected': false,
            'serviceId': 'PhoneUseAccessibilityService',
            'blockedReason': 'not_enabled',
          };
        default:
          return false;
      }
    });
    final provider = LinuxSandboxRuntimeProvider(
      nativeBridge: _InstalledLinuxSandboxBridge(),
      useNativeRunner: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CapabilityCenterScreen(
          linuxSandboxProvider: provider,
          includePreviewCliCatalog: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('能力中心'), findsOneWidget);
    expect(find.text('运行环境'), findsOneWidget);
    expect(find.text('扩展中心'), findsOneWidget);
    expect(find.text('账号订阅'), findsOneWidget);
    expect(find.text('安全权限'), findsOneWidget);
    expect(find.text('Sandbox 管理'), findsOneWidget);
    expect(find.text('Native Helper'), findsOneWidget);
    expect(find.text('Alpine Linux Sandbox'), findsOneWidget);
    expect(find.text('available'), findsWidgets);
    expect(find.text('needsSetup'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Termux fallback'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Termux fallback'), findsOneWidget);

    await tester.tap(find.text('扩展中心'));
    await tester.pumpAndSettle();
    expect(find.text('打开 CLI Hub'), findsOneWidget);
    expect(find.text('扩展中心 / CLI Hub'), findsOneWidget);
    expect(find.text('CLI Hub 摘要'), findsOneWidget);
    expect(find.textContaining('CLI 按需安装'), findsWidgets);
    expect(find.text('GitHub CLI'), findsNothing);
    expect(find.text('Google Workspace CLI'), findsNothing);

    await tester.tap(find.text('账号订阅'));
    await tester.pumpAndSettle();
    expect(find.text('ChatGPT / Codex'), findsOneWidget);
    expect(find.text('GitHub / Copilot'), findsOneWidget);
    expect(find.text('Google / Antigravity'), findsOneWidget);
    expect(find.text('打开 Usage Hub'), findsOneWidget);

    await tester.tap(find.text('安全权限'));
    await tester.pumpAndSettle();
    expect(find.text('权限设置'), findsOneWidget);
    expect(find.text('无障碍服务'), findsOneWidget);
    expect(find.text('后台运行权限'), findsOneWidget);
    expect(find.text('Credential Vault'), findsOneWidget);
    expect(find.text('Evidence / logs redaction'), findsOneWidget);

    await tester.tap(find.text('权限设置'));
    await tester.pumpAndSettle();
    expect(find.text('Harness 权限模式'), findsOneWidget);
    expect(find.text('Typed'), findsOneWidget);
  });
}

class _InstalledLinuxSandboxBridge implements LinuxSandboxNativeBridge {
  @override
  Future<Map<String, dynamic>> status() async => const {
        'installed': true,
        'ready': true,
        'status': 'ready',
        'arch': 'aarch64',
        'rootfsPath': '/app-owned/linux-sandbox/rootfs',
        'packages': {'base': true, 'devBasic': true},
      };

  @override
  Future<Map<String, dynamic>> setup(
    LinuxSandboxRootfsManifest manifest,
  ) async {
    return const {'success': true};
  }

  @override
  Future<Map<String, dynamic>> reset() async {
    return const {'success': true};
  }

  @override
  Future<Map<String, dynamic>> runTypedTask({
    required String taskKind,
    required Map<String, dynamic> payload,
  }) async {
    return {
      'success': true,
      'taskKind': taskKind,
      'status': 'succeeded',
      'stdout': '',
      'stderr': '',
      'exitCode': 0,
    };
  }
}
