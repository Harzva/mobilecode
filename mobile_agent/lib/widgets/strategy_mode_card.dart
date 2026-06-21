import 'dart:async';

import 'package:flutter/material.dart';

import '../services/reasoning_strategy_models.dart';
import '../services/reasoning_strategy_runner_contract.dart';
import '../services/strategy_dispatcher.dart';

class StrategyModeCard extends StatefulWidget {
  const StrategyModeCard({
    super.key,
    this.experimentalStrategiesEnabled = false,
    this.defaultGoal =
        'Run a MobileCode non-counted strategy trace for UI verification.',
  });

  final bool experimentalStrategiesEnabled;
  final String defaultGoal;

  @override
  State<StrategyModeCard> createState() => _StrategyModeCardState();
}

class _StrategyModeCardState extends State<StrategyModeCard> {
  _StrategyMode _selectedMode = _StrategyMode.auto;
  ReasoningStrategyRunOutput? _lastOutput;
  bool _running = false;

  Future<void> _runDryTrace() async {
    setState(() => _running = true);
    final mode = _selectedMode;
    final dispatcher = StrategyDispatcher.defaultSafe(
      capabilities: StrategyCapabilities(
        enableExperimentalSwarm: widget.experimentalStrategiesEnabled,
      ),
    );
    final output = await dispatcher.run(
      ReasoningStrategyRunInput(
        userGoal: widget.defaultGoal,
        memoryPacket: _memoryPacketFor(mode),
        strategyId: mode.strategyId,
        toolAccessPolicy: const {
          'allowed_tools': ['read_file', 'preview_html', 'evidence_record'],
          'task_category': 'code_preview',
        },
        maxSteps: 4,
      ),
    );
    if (!mounted) return;
    setState(() {
      _lastOutput = output;
      _running = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: const Color(0xFFFFFFFF),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFDDE7F7)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF7FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.account_tree_outlined,
                    color: Color(0xFF2555FF),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mobile Harness Strategy',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0B1020),
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Safe Auto is default; all UI traces are non-counted until real evidence passes.',
                        style: TextStyle(
                          color: Color(0xFF536079),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final mode in _StrategyMode.values)
                  ChoiceChip(
                    label: Text(mode.label),
                    selected: mode == _selectedMode,
                    onSelected: (_) => setState(() => _selectedMode = mode),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            _ModeDescription(mode: _selectedMode),
            if (_selectedMode.isExperimental &&
                !widget.experimentalStrategiesEnabled) ...[
              const SizedBox(height: 8),
              const _StatusPill(
                icon: Icons.lock_outline,
                text: 'Experimental gate is off',
                color: Color(0xFFB7791F),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _running ? null : () => unawaited(_runDryTrace()),
              icon: _running
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow_outlined),
              label: Text(_running ? 'Running dry trace' : 'Run dry trace'),
            ),
            const SizedBox(height: 12),
            _StrategyRunSummary(output: _lastOutput),
          ],
        ),
      ),
    );
  }

  HarnessMemoryPacket _memoryPacketFor(_StrategyMode mode) =>
      HarnessMemoryPacket(
        packetId: 'hmp_ui_${mode.name}',
        schemaVersion: '0.1.0',
        sessionId: 'mobilecode-ui',
        runId: 'ui-${mode.name}',
        createdAt: DateTime.now().toUtc(),
        ttlSeconds: 86400,
        sourceLimits: const HarnessSourceLimits(recentTurns: 4, maxChars: 2400),
        userGoal: widget.defaultGoal,
        conversationSummary: 'UI dry trace summary only.',
        recentTurns: const [
          HarnessRecentTurn(
            role: 'user',
            summary: 'User requested MobileCode strategy UI verification.',
          ),
        ],
        activeConstraints: const [
          'no provider call',
          'no raw transcript',
          'non-counted UI dry trace',
        ],
        redaction: const HarnessRedaction(
          applied: true,
          classes: ['secret', 'absolute_private_path', 'raw_transcript'],
        ),
      );
}

class _ModeDescription extends StatelessWidget {
  const _ModeDescription({required this.mode});

  final _StrategyMode mode;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFF7FAFF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFDDE7F7)),
        ),
        child: Text(
          mode.description,
          style: const TextStyle(color: Color(0xFF536079), fontSize: 12),
        ),
      );
}

class _StrategyRunSummary extends StatelessWidget {
  const _StrategyRunSummary({required this.output});

  final ReasoningStrategyRunOutput? output;

  @override
  Widget build(BuildContext context) {
    final output = this.output;
    if (output == null) {
      return const Text(
        'No trace yet. Run a dry trace to verify strategy UI wiring.',
        style: TextStyle(color: Color(0xFF536079), fontSize: 12),
      );
    }
    final blockedReason = output.trace.failureKind ?? 'none';
    final memory = output.trace.traceId.split('_').take(2).join('_');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SummaryLine('Current strategy: ${output.trace.strategyId}'),
        _SummaryLine('Run status: ${output.runKind}'),
        _SummaryLine('counts_as_experiment=${output.countsAsExperiment}'),
        _SummaryLine('Trace events: ${output.trace.events.length}'),
        _SummaryLine('Evidence records: ${output.actionEvidence.length}'),
        _SummaryLine('Blocked reason: $blockedReason'),
        _SummaryLine(
          'Retry/replan: recovered ${output.effectMetrics.verificationFailuresRecovered ?? 0}, replans ${output.effectMetrics.planningRevisions ?? 0}',
        ),
        _SummaryLine(
          'Handoff summary: ${output.trace.handoffCount} handoffs',
        ),
        _SummaryLine('Memory packet: $memory, TTL 86400s, summary only'),
      ],
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          text,
          style: const TextStyle(
            color: Color(0xFF0B1020),
            fontSize: 12,
            height: 1.25,
          ),
        ),
      );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}

enum _StrategyMode {
  auto,
  react,
  planExecuteVerify,
  supervisorHandoff,
  experimentalSwarm;

  String get label => switch (this) {
        _StrategyMode.auto => 'Auto',
        _StrategyMode.react => 'ReAct',
        _StrategyMode.planExecuteVerify => 'Plan-Execute-Verify',
        _StrategyMode.supervisorHandoff => 'Supervisor/Handoff',
        _StrategyMode.experimentalSwarm => 'Experimental Swarm',
      };

  String get strategyId => switch (this) {
        _StrategyMode.auto => planExecuteVerifySingleAgentStrategyId,
        _StrategyMode.react => reactSingleAgentStrategyId,
        _StrategyMode.planExecuteVerify =>
          planExecuteVerifySingleAgentStrategyId,
        _StrategyMode.supervisorHandoff =>
          supervisorHandoffMultiAgentStrategyId,
        _StrategyMode.experimentalSwarm => swarmRouterMultiAgentStrategyId,
      };

  String get description => switch (this) {
        _StrategyMode.auto =>
          'Safe Auto routes to Plan-Execute-Verify and keeps outputs non-counted.',
        _StrategyMode.react =>
          'ReAct emits think, act, observe, repeat, and report events.',
        _StrategyMode.planExecuteVerify =>
          'PEV plans 3-7 verifiable steps, executes, verifies, and records retry/replan state.',
        _StrategyMode.supervisorHandoff =>
          'Supervisor/Handoff routes through specialist packets with filtered context.',
        _StrategyMode.experimentalSwarm =>
          'Experimental Swarm is visible for release QA but blocked until the feature gate is enabled.',
      };

  bool get isExperimental => this == _StrategyMode.experimentalSwarm;
}
