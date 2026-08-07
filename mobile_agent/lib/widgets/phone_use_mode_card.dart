import 'dart:async';

import 'package:flutter/material.dart';

import '../services/device_automation_provider.dart';
import '../services/phone_use_accessibility_service.dart';

class PhoneUseModeCard extends StatefulWidget {
  const PhoneUseModeCard({
    super.key,
    this.deviceAutomationCoordinator,
    this.credentialSlotService,
  });

  final DeviceAutomationCoordinator? deviceAutomationCoordinator;
  final PhoneUseCredentialSlotService? credentialSlotService;

  @override
  State<PhoneUseModeCard> createState() => _PhoneUseModeCardState();
}

class _PhoneUseModeCardState extends State<PhoneUseModeCard> {
  static Map<String, dynamic>? _cachedLastProbe;
  static Map<String, dynamic>? _cachedLastActionProbe;
  static String? _cachedProbeFieldValue;

  final _probeFieldKey = GlobalKey();
  final _probeFieldController = TextEditingController();
  final _probeFocusNode = FocusNode();
  final _credentialSlotController = TextEditingController();
  final _credentialValueController = TextEditingController();
  late final DeviceAutomationCoordinator _deviceAutomationCoordinator;
  late final PhoneUseCredentialSlotService _credentialSlotService;
  PhoneUseAccessibilityStatus? _status;
  Map<String, dynamic>? _lastProbe;
  Map<String, dynamic>? _lastActionProbe;
  bool _checking = false;
  bool _running = false;
  bool _runningActionProbe = false;
  bool _savingCredential = false;
  String? _credentialStatus;

  @override
  void dispose() {
    _probeFieldController.dispose();
    _probeFocusNode.dispose();
    _credentialSlotController.dispose();
    _credentialValueController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _deviceAutomationCoordinator = widget.deviceAutomationCoordinator ??
        DeviceAutomationCoordinator(
          provider: EmbeddedAccessibilityDeviceAutomationProvider(),
        );
    _credentialSlotService =
        widget.credentialSlotService ?? PhoneUseCredentialSlotService();
    _lastProbe = _cachedLastProbe;
    _lastActionProbe = _cachedLastActionProbe;
    final cachedProbeFieldValue = _cachedProbeFieldValue;
    if (cachedProbeFieldValue != null) {
      _probeFieldController.text = cachedProbeFieldValue;
    }
    unawaited(_refreshStatus());
  }

  Future<void> _refreshStatus() async {
    setState(() => _checking = true);
    final status = await PhoneUseAccessibilityService.instance.getStatus();
    if (!mounted) return;
    setState(() {
      _status = status;
      _checking = false;
    });
  }

  Future<void> _openSettings() async {
    await PhoneUseAccessibilityService.instance.openAccessibilitySettings();
    if (!mounted) return;
    await _refreshStatus();
  }

  Future<void> _runDryProbe() async {
    setState(() => _running = true);
    final execution = await _deviceAutomationCoordinator.execute(
      const DeviceAutomationRequest(action: DeviceAutomationActionKind.observe),
    );
    final probe = {
      ...execution.result.data,
      'evidenceId': execution.evidence.evidenceId,
    };
    final status = await PhoneUseAccessibilityService.instance.getStatus();
    if (!mounted) return;
    setState(() {
      _lastProbe = probe;
      _cachedLastProbe = probe;
      _status = status;
      _running = false;
    });
  }

  Future<void> _runActionProbe() async {
    setState(() => _runningActionProbe = true);
    final actions = <Map<String, dynamic>>[];

    Future<DeviceAutomationExecution> runAction(
      DeviceAutomationRequest request,
    ) async {
      final execution = await _deviceAutomationCoordinator.execute(request);
      final result = execution.result.data;
      actions.add({
        'type': request.action.name,
        'status': result['status'],
        'accepted': execution.success,
        'failureKind': execution.evidence.failureKind,
        'evidenceId': execution.evidence.evidenceId,
      });
      return execution;
    }

    _probeFieldController.clear();
    _probeFocusNode.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 350));

    final observation = await runAction(
      const DeviceAutomationRequest(action: DeviceAutomationActionKind.observe),
    );
    final snapshotMap = _mapValue(
      observation.result.data['snapshot'] ??
          observation.result.data['observation'],
    );
    var snapshot = snapshotMap.isEmpty
        ? null
        : PhoneUseSemanticSnapshot.fromMap(snapshotMap);
    PhoneUseSemanticNode? findEditable(PhoneUseSemanticSnapshot? value) {
      for (final node in value?.nodes ?? const <PhoneUseSemanticNode>[]) {
        if (node.editable && node.enabled) return node;
      }
      return null;
    }

    var editable = findEditable(snapshot);
    if (editable != null && snapshot?.refsGeneration != null) {
      await runAction(
        DeviceAutomationRequest(
          action: DeviceAutomationActionKind.tapRef,
          targetRef: editable.pinnedRef(snapshot!.refsGeneration!),
          approvalGranted: true,
          approvalSource: 'phone_use_probe_button',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final refreshedObservation = await runAction(
        const DeviceAutomationRequest(
          action: DeviceAutomationActionKind.observe,
        ),
      );
      final refreshedSnapshotMap = _mapValue(
        refreshedObservation.result.data['snapshot'] ??
            refreshedObservation.result.data['observation'],
      );
      snapshot = refreshedSnapshotMap.isEmpty
          ? null
          : PhoneUseSemanticSnapshot.fromMap(refreshedSnapshotMap);
      editable = findEditable(snapshot);
    }

    if (editable == null) {
      _probeFocusNode.requestFocus();
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    await runAction(
      DeviceAutomationRequest(
        action: editable == null
            ? DeviceAutomationActionKind.setTextFocused
            : DeviceAutomationActionKind.setTextRef,
        targetRef: editable == null || snapshot?.refsGeneration == null
            ? null
            : editable.pinnedRef(snapshot!.refsGeneration!),
        text: 'phone use probe',
        approvalGranted: true,
        approvalSource: 'phone_use_probe_button',
      ),
    );

    final fieldBox =
        _probeFieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (fieldBox != null) {
      final center = fieldBox.localToGlobal(
        Offset(fieldBox.size.width / 2, fieldBox.size.height / 2),
      );
      await runAction(
        DeviceAutomationRequest(
          action: DeviceAutomationActionKind.tapCoordinate,
          x: center.dx.round(),
          y: center.dy.round(),
          approvalGranted: true,
          approvalSource: 'phone_use_probe_button',
        ),
      );
      await runAction(
        DeviceAutomationRequest(
          action: DeviceAutomationActionKind.swipe,
          x: (center.dx + 80).round(),
          y: center.dy.round(),
          x2: (center.dx - 80).round(),
          y2: center.dy.round(),
          durationMs: 180,
          approvalGranted: true,
          approvalSource: 'phone_use_probe_button',
        ),
      );
    } else {
      actions.add({
        'type': 'tap',
        'status': 'blocked',
        'accepted': false,
        'failureKind': 'probe_target_unavailable',
      });
      actions.add({
        'type': 'swipe',
        'status': 'blocked',
        'accepted': false,
        'failureKind': 'probe_target_unavailable',
      });
    }

    final status = await PhoneUseAccessibilityService.instance.getStatus();
    final accepted = actions.where((action) => action['accepted'] == true);
    final textSet = _probeFieldController.text == 'phone use probe';
    final actionProbe = {
      'status':
          accepted.length == actions.length && textSet ? 'passed' : 'warning',
      'actions': actions,
      'acceptedCount': accepted.length,
      'totalActions': actions.length,
      'textLength': _probeFieldController.text.length,
      'textSet': textSet,
      'homeAccepted': false,
      'homeScheduled': false,
      'countsAsExperiment': false,
      'countsAsStrategyAblationResult': false,
      'rawTextIncluded': false,
      'redactionApplied': true,
      'evidenceIds': actions
          .map((action) => action['evidenceId'])
          .whereType<String>()
          .toList(growable: false),
    };
    _cachedLastActionProbe = actionProbe;
    _cachedProbeFieldValue = _probeFieldController.text;
    if (!mounted) return;
    setState(() {
      _lastActionProbe = actionProbe;
      _status = status;
      _runningActionProbe = false;
    });
  }

  Future<void> _storeCredentialSlot() async {
    final slotId = _credentialSlotController.text;
    final value = _credentialValueController.text;
    setState(() {
      _savingCredential = true;
      _credentialStatus = null;
    });
    try {
      await _credentialSlotService.store(slotId, value);
      _credentialValueController.clear();
      if (!mounted) return;
      setState(() => _credentialStatus = 'Stored locally as $slotId.');
    } on Object {
      if (!mounted) return;
      setState(() => _credentialStatus =
          'Credential slot was not stored. Check the slot ID and device lock.');
    } finally {
      if (mounted) setState(() => _savingCredential = false);
    }
  }

  Future<void> _deleteCredentialSlot() async {
    final slotId = _credentialSlotController.text;
    setState(() {
      _savingCredential = true;
      _credentialStatus = null;
    });
    try {
      await _credentialSlotService.delete(slotId);
      _credentialValueController.clear();
      if (!mounted) return;
      setState(() => _credentialStatus = 'Deleted local slot $slotId.');
    } on Object {
      if (!mounted) return;
      setState(() => _credentialStatus =
          'Credential slot was not deleted. Check the slot ID and device lock.');
    } finally {
      if (mounted) setState(() => _savingCredential = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _status;
    final ready = status?.ready == true;
    final blockedReason =
        _probeString('failureKind') ?? status?.blockedReason ?? 'none';
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
                    Icons.accessibility_new_outlined,
                    color: Color(0xFF2555FF),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mobile Phone Use',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0B1020),
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Accessibility-gated UI observe/action probe; all traces are non-counted.',
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
                _StatusPill(
                  icon: ready ? Icons.check_circle_outline : Icons.lock_outline,
                  text: ready ? 'Ready' : 'Permission gated',
                  color:
                      ready ? const Color(0xFF047857) : const Color(0xFFB7791F),
                ),
                const _StatusPill(
                  icon: Icons.fact_check_outlined,
                  text: 'counts_as_experiment=false',
                  color: Color(0xFF2555FF),
                ),
                if (status?.serviceConnected == true)
                  const _StatusPill(
                    icon: Icons.link_outlined,
                    text: 'Service connected',
                    color: Color(0xFF047857),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed:
                      _checking ? null : () => unawaited(_refreshStatus()),
                  icon: _checking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_outlined),
                  label: Text(_checking ? 'Checking' : 'Refresh'),
                ),
                OutlinedButton.icon(
                  onPressed: () => unawaited(_openSettings()),
                  icon: const Icon(Icons.settings_accessibility_outlined),
                  label: const Text('Open settings'),
                ),
                FilledButton.icon(
                  onPressed: _running ? null : () => unawaited(_runDryProbe()),
                  icon: _running
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow_outlined),
                  label: Text(_running ? 'Running dry probe' : 'Run dry probe'),
                ),
                FilledButton.icon(
                  onPressed: _runningActionProbe
                      ? null
                      : () => unawaited(_runActionProbe()),
                  icon: _runningActionProbe
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.touch_app_outlined),
                  label: Text(
                    _runningActionProbe
                        ? 'Running action probe'
                        : 'Run action probe',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              key: _probeFieldKey,
              controller: _probeFieldController,
              focusNode: _probeFocusNode,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Probe target',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: const Text(
                'Controlled credential slot',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              ),
              subtitle: const Text(
                'Stored in Keystore/Keychain. Agent evidence records only secret_id.',
                style: TextStyle(fontSize: 11.5),
              ),
              children: [
                TextField(
                  controller: _credentialSlotController,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Slot ID (for example takeout.qa.password)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _credentialValueController,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Credential value',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _savingCredential
                          ? null
                          : () => unawaited(_storeCredentialSlot()),
                      icon: const Icon(Icons.lock_outline),
                      label: const Text('Store locally'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _savingCredential
                          ? null
                          : () => unawaited(_deleteCredentialSlot()),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete slot'),
                    ),
                  ],
                ),
                if (_credentialStatus != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _credentialStatus!,
                    style: const TextStyle(
                      color: Color(0xFF536079),
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            _PhoneUseSummary(
              status: status,
              probe: _lastProbe,
              actionProbe: _lastActionProbe,
              blockedReason: blockedReason,
            ),
          ],
        ),
      ),
    );
  }

  String? _probeString(String key) {
    final value = _lastProbe?[key];
    if (value == null) return null;
    final text = value.toString();
    return text.isEmpty ? null : text;
  }
}

class _PhoneUseSummary extends StatelessWidget {
  const _PhoneUseSummary({
    required this.status,
    required this.probe,
    required this.actionProbe,
    required this.blockedReason,
  });

  final PhoneUseAccessibilityStatus? status;
  final Map<String, dynamic>? probe;
  final Map<String, dynamic>? actionProbe;
  final String blockedReason;

  @override
  Widget build(BuildContext context) {
    final status = this.status;
    if (status == null) {
      return const Text(
        'No status yet. Refresh to check the phone-use permission gate.',
        style: TextStyle(color: Color(0xFF536079), fontSize: 12),
      );
    }
    final observation = _mapValue(probe?['observation']);
    final actions = status.supportedActions.isEmpty
        ? 'none'
        : status.supportedActions.join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SummaryLine('Platform: ${status.platform}'),
        _SummaryLine(
          'Accessibility: enabled=${status.accessibilityEnabled}, connected=${status.serviceConnected}',
        ),
        _SummaryLine('Lifecycle: ${status.lifecycleState.wireValue}'),
        _SummaryLine(
          'Capabilities: observe=${status.canObserveActiveWindow}, gestures=${status.canPerformGestures}, text=${status.canSetText}, screenshot=${status.canCaptureScreenshot}',
        ),
        _SummaryLine(
          'Background: restricted=${status.backgroundRestricted}, battery_exempt=${status.batteryOptimizationIgnored}',
        ),
        _SummaryLine('Supported actions: $actions'),
        _SummaryLine(
          'counts_as_experiment=${status.countsAsExperiment}',
        ),
        _SummaryLine('raw_text_included=${status.rawTextIncluded}'),
        _SummaryLine('Blocked reason: $blockedReason'),
        if (probe != null) ...[
          _SummaryLine('Dry probe status: ${probe!['status'] ?? 'unknown'}'),
          _SummaryLine(
            'Observed nodes: ${observation['nodeCount'] ?? 0}, clickable ${observation['clickableNodeCount'] ?? 0}, editable ${observation['editableNodeCount'] ?? 0}',
          ),
          _SummaryLine(
            'Semantic frame: ${observation['frameId'] ?? 'none'} state=${observation['frameState'] ?? 'none'} digest=${observation['digest'] ?? 'none'}',
          ),
          _SummaryLine(
            'Foreground: ${observation['rootPackageNameHash'] ?? 'unknown'} / ${observation['rootClassName'] ?? 'unknown'}',
          ),
        ],
        if (actionProbe != null) ...[
          _SummaryLine(
            'Action probe status: ${actionProbe!['status'] ?? 'unknown'}',
          ),
          _SummaryLine(
            'Actions accepted: ${actionProbe!['acceptedCount'] ?? 0}/${actionProbe!['totalActions'] ?? 0}',
          ),
          _SummaryLine('Set text: ${actionProbe!['textSet'] ?? false}'),
          _SummaryLine(
            'Home scheduled: ${actionProbe!['homeScheduled'] ?? false}',
          ),
          _SummaryLine('Home action: ${actionProbe!['homeAccepted'] ?? false}'),
          for (final action in _actionDetails(actionProbe!))
            _SummaryLine(
              'Action detail: ${action['type']} ${action['status']} accepted=${action['accepted']} failure=${action['failureKind'] ?? 'none'}',
            ),
        ],
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

Map<String, dynamic> _mapValue(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

List<Map<String, dynamic>> _actionDetails(Map<String, dynamic> actionProbe) {
  final actions = actionProbe['actions'];
  if (actions is! List) return const [];
  return actions
      .whereType<Map<dynamic, dynamic>>()
      .map((action) => Map<String, dynamic>.from(action))
      .toList();
}
