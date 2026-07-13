import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/widgets/agent_trace_progress_box.dart';

void main() {
  testWidgets('shows running progress for a CLI Hub typed task',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AgentTraceProgressBox(
            metadata: {
              'cliTitle': 'GitHub CLI',
              'cliId': 'github-cli',
              'taskKind': 'package_install',
              'runtime': 'linuxSandbox',
              'taskId': 'task-123',
              'status': 'running',
            },
            color: Colors.amber,
            running: true,
          ),
        ),
      ),
    );

    expect(find.text('Task running'), findsOneWidget);
    expect(find.text('running'), findsOneWidget);
    expect(find.textContaining('GitHub CLI'), findsOneWidget);
    expect(find.textContaining('package_install'), findsOneWidget);
    expect(find.textContaining('task:task-123'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('shows a compact task event without an indeterminate bar',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AgentTraceProgressBox(
            metadata: {
              'cliId': 'github-cli',
              'taskKind': 'github_cli_execute',
              'commandId': 'repo_list',
              'runtimeStatus': 'succeeded',
            },
            color: Colors.green,
            running: false,
          ),
        ),
      ),
    );

    expect(find.text('Task event'), findsOneWidget);
    expect(find.text('succeeded'), findsOneWidget);
    expect(find.textContaining('command:repo_list'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
