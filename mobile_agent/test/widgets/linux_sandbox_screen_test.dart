import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/screens/linux_sandbox_screen.dart';
import 'package:mobile_agent/screens/settings_screen.dart';
import 'package:mobile_agent/widgets/linux_sandbox_task_card.dart';

void main() {
  testWidgets('shows Linux Sandbox rootfs unavailable state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LinuxSandboxScreen(),
      ),
    );

    expect(find.text('Linux Sandbox'), findsOneWidget);
    expect(find.text('Alpine Linux rootfs'), findsOneWidget);
    expect(find.textContaining('未安装'), findsOneWidget);
    expect(find.text('Package Profiles'), findsOneWidget);
    expect(find.text('Base'), findsOneWidget);
    expect(find.text('Dev Basic'), findsOneWidget);
    expect(find.text('Python Pack'), findsOneWidget);
    expect(find.text('Node Pack'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('linuxSandbox.installRootfs')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('linuxSandbox.installRootfs')),
        findsOneWidget);

    await tester.scrollUntilVisible(
      find.textContaining('Security gate'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    expect(find.textContaining('Security gate'), findsOneWidget);
    expect(find.textContaining('raw shell'), findsWidgets);
    expect(
        find.byKey(const ValueKey('linuxSandbox.copyCommand')), findsOneWidget);
  });

  testWidgets('settings exposes Linux Sandbox entry', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SettingsScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    await tester.scrollUntilVisible(
      find.text('运行时'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('运行时'), findsOneWidget);
    expect(find.text('Linux Sandbox'), findsOneWidget);
    expect(find.textContaining('内置 Alpine rootfs'), findsOneWidget);
  });

  testWidgets('task card exposes typed handoff preview and copy action',
      (tester) async {
    var runCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LinuxSandboxTaskCard(
            installed: true,
            preview: const LinuxSandboxTaskPreview(
              taskKind: 'npm_build',
              cwd: '/workspace/app',
              args: ['--release'],
              timeout: Duration(seconds: 60),
              capability: 'nodePack',
              impact: '写入 build 输出',
            ),
            onRun: () => runCount++,
          ),
        ),
      ),
    );

    expect(find.text('npm_build'), findsOneWidget);
    expect(find.text('/workspace/app'), findsOneWidget);
    expect(find.text('Run in Linux Sandbox'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('linuxSandbox.runTask')));
    await tester.pump();

    expect(runCount, 1);
  });
}
