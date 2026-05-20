import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../services/device_telemetry_service.dart';

const _deviceBg = Color(0xFFF7FAFF);
const _devicePanel = Color(0xFFFFFFFF);
const _deviceLine = Color(0xFFDDE7F7);
const _deviceText = Color(0xFF0B1020);
const _deviceMuted = Color(0xFF536079);
const _deviceFaint = Color(0xFF8B97AD);
const _deviceMint = Color(0xFF0B9B7E);
const _deviceCyan = Color(0xFF16B9C7);
const _deviceAmber = Color(0xFFB7791F);
const _deviceRose = Color(0xFFE0526E);
const _deviceViolet = Color(0xFF7557E8);

class DeviceTelemetryScreen extends StatefulWidget {
  const DeviceTelemetryScreen({super.key});

  @override
  State<DeviceTelemetryScreen> createState() => _DeviceTelemetryScreenState();
}

class _DeviceTelemetryScreenState extends State<DeviceTelemetryScreen> {
  late final Stream<DeviceTelemetrySnapshot> _stream;
  var _frameWindowStart = DateTime.now();
  var _frameCount = 0;
  var _jankCount = 0;
  var _fps = 0.0;
  var _jankPercent = 0.0;

  @override
  void initState() {
    super.initState();
    _stream = DeviceTelemetryService.instance.watchTelemetry();
    SchedulerBinding.instance.addTimingsCallback(_handleFrameTimings);
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_handleFrameTimings);
    super.dispose();
  }

  void _handleFrameTimings(List<FrameTiming> timings) {
    _frameCount += timings.length;
    _jankCount += timings.where((timing) => timing.totalSpan.inMilliseconds > 16).length;
    final elapsed = DateTime.now().difference(_frameWindowStart);
    if (elapsed.inMilliseconds < 900 || !mounted) return;
    setState(() {
      _fps = _frameCount * 1000 / elapsed.inMilliseconds;
      _jankPercent = _frameCount == 0 ? 0 : _jankCount * 100 / _frameCount;
      _frameCount = 0;
      _jankCount = 0;
      _frameWindowStart = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _deviceBg,
      appBar: AppBar(
        title: const Text('Device Telemetry'),
        backgroundColor: _deviceBg,
        foregroundColor: _deviceText,
        elevation: 0,
      ),
      body: StreamBuilder<DeviceTelemetrySnapshot>(
        stream: _stream,
        builder: (context, snapshot) {
          final data = snapshot.data;
          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _DeviceHeader(snapshot: data),
              const SizedBox(height: 12),
              _MetricGrid(snapshot: data),
              const SizedBox(height: 12),
              _DevicePanel(
                title: 'htop snapshot',
                icon: Icons.monitor_heart_outlined,
                color: _deviceMint,
                children: [
                  _TelemetryBar(
                    label: 'CPU',
                    valueLabel: '${data.cpuUsagePercent.toStringAsFixed(1)}%',
                    value: (data.cpuUsagePercent / 100).clamp(0, 1),
                    color: _deviceMint,
                  ),
                  _TelemetryBar(
                    label: 'RAM',
                    valueLabel: data.totalMemoryMb > 0
                        ? '${data.availableMemoryMb} MB free / ${data.totalMemoryMb} MB'
                        : 'Unknown',
                    value: data.memoryUsedPercent.clamp(0, 1),
                    color: data.lowMemory ? _deviceRose : _deviceCyan,
                  ),
                  _TelemetryBar(
                    label: 'Storage',
                    valueLabel: data.storageTotalMb > 0
                        ? '${data.storageFreeMb} MB free / ${data.storageTotalMb} MB'
                        : 'Unknown',
                    value: data.storageUsedPercent.clamp(0, 1),
                    color: _deviceAmber,
                  ),
                  _TelemetryBar(
                    label: 'Battery',
                    valueLabel: data.batteryLevel >= 0
                        ? '${data.batteryLevel}%${data.batteryCharging ? ' charging' : ''}'
                        : 'Unknown',
                    value: data.batteryPercent.clamp(0, 1),
                    color: data.batteryCharging ? _deviceMint : _deviceViolet,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _DevicePanel(
                title: 'Runtime pressure',
                icon: Icons.memory_outlined,
                color: _deviceViolet,
                children: [
                  _InfoRow(label: 'App RSS', value: '${data.appRssMb} MB'),
                  _InfoRow(label: 'App heap/native', value: '${data.appHeapMb} MB'),
                  _InfoRow(label: 'FPS / jank', value: '${_fps.toStringAsFixed(0)} fps / ${_jankPercent.toStringAsFixed(1)}%'),
                  _InfoRow(label: 'CPU cores', value: '${data.cpuCores}'),
                  _InfoRow(label: 'Thermal status', value: _thermalLabel(data.thermalStatus)),
                  _InfoRow(
                    label: 'Battery temperature',
                    value: data.batteryTemperatureC > 0 ? '${data.batteryTemperatureC.toStringAsFixed(1)} C' : 'Unknown',
                  ),
                  _InfoRow(label: 'Last sample', value: _timeLabel(data.timestamp)),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DeviceHeader extends StatelessWidget {
  const _DeviceHeader({required this.snapshot});

  final DeviceTelemetrySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return _DevicePanel(
      title: 'Phone profile',
      icon: Icons.phone_android_outlined,
      color: _deviceCyan,
      trailing: snapshot.fallback
          ? const _Badge(label: 'fallback', color: _deviceAmber)
          : const _Badge(label: 'native', color: _deviceMint),
      children: [
        Text(
          [snapshot.manufacturer, snapshot.model].where((item) => item.trim().isNotEmpty).join(' ').trim().isEmpty
              ? snapshot.model
              : [snapshot.manufacturer, snapshot.model].where((item) => item.trim().isNotEmpty).join(' '),
          style: const TextStyle(color: _deviceText, fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          [
            snapshot.platform,
            if (snapshot.androidVersion.isNotEmpty) 'Android ${snapshot.androidVersion}',
            if (snapshot.sdkInt > 0) 'SDK ${snapshot.sdkInt}',
            if (snapshot.abis.isNotEmpty) snapshot.abis.take(2).join(', '),
          ].join(' · '),
          style: const TextStyle(color: _deviceMuted, fontSize: 12, height: 1.35),
        ),
      ],
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.snapshot});

  final DeviceTelemetrySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 560 ? 4 : 2;
        return GridView.count(
          crossAxisCount: columns,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: columns == 4 ? 1.9 : 1.45,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _MetricTile(label: 'CPU', value: '${snapshot.cpuUsagePercent.toStringAsFixed(0)}%', icon: Icons.speed_outlined, color: _deviceMint),
            _MetricTile(label: 'RAM free', value: snapshot.availableMemoryMb > 0 ? '${snapshot.availableMemoryMb} MB' : 'Unknown', icon: Icons.memory_outlined, color: _deviceCyan),
            _MetricTile(label: 'Battery', value: snapshot.batteryLevel >= 0 ? '${snapshot.batteryLevel}%' : 'Unknown', icon: Icons.battery_charging_full_outlined, color: _deviceAmber),
            _MetricTile(label: 'App RSS', value: '${snapshot.appRssMb} MB', icon: Icons.data_usage_outlined, color: _deviceViolet),
          ],
        );
      },
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _devicePanel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _deviceLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 20),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _deviceText, fontSize: 20, fontWeight: FontWeight.w900)),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _deviceMuted, fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _DevicePanel extends StatelessWidget {
  const _DevicePanel({
    required this.title,
    required this.icon,
    required this.color,
    required this.children,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _devicePanel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _deviceLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: const TextStyle(color: _deviceText, fontSize: 14, fontWeight: FontWeight.w900))),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _TelemetryBar extends StatelessWidget {
  const _TelemetryBar({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.color,
  });

  final String label;
  final String valueLabel;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: const TextStyle(color: _deviceText, fontSize: 12, fontWeight: FontWeight.w900))),
              Text(valueLabel, style: const TextStyle(color: _deviceMuted, fontSize: 11, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 8,
              backgroundColor: color.withOpacity(0.12),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: _deviceMuted, fontSize: 12, fontWeight: FontWeight.w700))),
          Flexible(child: Text(value, textAlign: TextAlign.right, style: const TextStyle(color: _deviceText, fontSize: 12, fontWeight: FontWeight.w900))),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900)),
    );
  }
}

String _thermalLabel(int status) {
  return switch (status) {
    0 => 'None',
    1 => 'Light',
    2 => 'Moderate',
    3 => 'Severe',
    4 => 'Critical',
    5 => 'Emergency',
    6 => 'Shutdown',
    _ => 'Unknown',
  };
}

String _timeLabel(DateTime value) {
  final h = value.hour.toString().padLeft(2, '0');
  final m = value.minute.toString().padLeft(2, '0');
  final s = value.second.toString().padLeft(2, '0');
  return '$h:$m:$s';
}
