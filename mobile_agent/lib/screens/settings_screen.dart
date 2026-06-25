import 'dart:async';

import 'package:flutter/material.dart';
import '../services/phone_use_accessibility_service.dart';
import '../themes/app_theme.dart';
import '../widgets/glass_card_widget.dart';
import 'github_screen.dart';
import 'api_config_screen.dart';

/// App Settings screen
/// Editor settings, theme, AI assistant, GitHub, About, Data management
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Editor settings
  double _fontSize = 14.0;
  String _fontFamily = 'JetBrainsMono';
  bool _showLineNumbers = true;
  bool _wordWrap = true;

  // Theme settings
  String _themeMode = 'dark'; // dark, light, system

  // AI settings
  String _defaultApi = 'Custom Provider / Base URL';
  double _temperature = 0.7;

  // GitHub
  bool _githubConnected = true;
  String? _githubUsername = 'devuser';

  // System permissions
  PhoneUseAccessibilityStatus? _phoneUseStatus;
  bool _permissionChecking = false;

  // App info
  final String _appVersion = '1.0.0';
  final String _buildNumber = '100';

  final List<String> _fontFamilies = [
    'JetBrainsMono',
    'FiraCode',
    'CascadiaCode',
    'SourceCodePro',
    'Consolas',
    'Monaco',
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_refreshPhoneUseStatus());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.deepSpace,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Header
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Text(
                  '更多',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ),

            // ── Editor Section ──
            _buildSectionHeader('编辑器', Icons.code),
            SliverToBoxAdapter(
              child: _buildSettingCard([
                // Font size slider
                _buildSliderSetting(
                  icon: Icons.format_size,
                  title: '字体大小',
                  subtitle: '${_fontSize.toInt()}pt',
                  value: _fontSize,
                  min: 10,
                  max: 24,
                  divisions: 14,
                  onChanged: (v) => setState(() => _fontSize = v),
                ),
                const Divider(color: AppTheme.divider, height: 1),
                // Font family
                _buildDropdownSetting(
                  icon: Icons.font_download,
                  title: '字体',
                  value: _fontFamily,
                  items: _fontFamilies,
                  onChanged: (v) => setState(() => _fontFamily = v!),
                ),
                const Divider(color: AppTheme.divider, height: 1),
                // Line numbers
                _buildToggleSetting(
                  icon: Icons.format_list_numbered,
                  title: '显示行号',
                  value: _showLineNumbers,
                  onChanged: (v) => setState(() => _showLineNumbers = v),
                ),
                const Divider(color: AppTheme.divider, height: 1),
                // Word wrap
                _buildToggleSetting(
                  icon: Icons.wrap_text,
                  title: '自动换行',
                  value: _wordWrap,
                  onChanged: (v) => setState(() => _wordWrap = v),
                ),
              ]),
            ),

            // ── Theme Section ──
            _buildSectionHeader('主题', Icons.palette),
            SliverToBoxAdapter(
              child: _buildSettingCard([
                _buildThemeSelector(),
              ]),
            ),

            // ── AI Assistant Section ──
            _buildSectionHeader('AI 助手', Icons.auto_awesome),
            SliverToBoxAdapter(
              child: _buildSettingCard([
                // Default API
                _buildNavigationSetting(
                  icon: Icons.psychology,
                  title: '默认 API',
                  subtitle: _defaultApi,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ApiConfigScreen(),
                    ),
                  ),
                ),
                const Divider(color: AppTheme.divider, height: 1),
                // Temperature slider
                _buildSliderSetting(
                  icon: Icons.thermostat,
                  title: 'Temperature',
                  subtitle: _temperature.toStringAsFixed(1),
                  value: _temperature,
                  min: 0.0,
                  max: 2.0,
                  divisions: 20,
                  onChanged: (v) => setState(() => _temperature = v),
                ),
              ]),
            ),

            // ── GitHub Section ──
            _buildSectionHeader('GitHub', Icons.hub),
            SliverToBoxAdapter(
              child: _buildSettingCard([
                ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: AppTheme.auroraGradient,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Center(
                      child: Text(
                        (_githubUsername ?? 'G')[0].toUpperCase(),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  title: Text(
                    _githubConnected ? '已连接: $_githubUsername' : '未连接',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    _githubConnected ? '点击管理连接' : '点击连接 GitHub',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textTertiary,
                    ),
                  ),
                  trailing: _githubConnected
                      ? TextButton(
                          onPressed: () => _showDisconnectDialog(),
                          child: const Text(
                            '断开',
                            style: TextStyle(color: AppTheme.error),
                          ),
                        )
                      : const Icon(Icons.chevron_right,
                          color: AppTheme.textTertiary),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const GitHubScreen(),
                    ),
                  ),
                ),
              ]),
            ),

            // ── System Permissions Section ──
            _buildSectionHeader('系统权限', Icons.admin_panel_settings_outlined),
            SliverToBoxAdapter(
              child: _buildSettingCard([
                _buildAccessibilitySetting(),
                const Divider(color: AppTheme.divider, height: 1),
                _buildBackgroundPermissionSetting(),
              ]),
            ),

            // ── About Section ──
            _buildSectionHeader('关于', Icons.info_outline),
            SliverToBoxAdapter(
              child: _buildSettingCard([
                _buildInfoRow('版本', _appVersion),
                const Divider(color: AppTheme.divider, height: 1),
                _buildInfoRow('构建号', _buildNumber),
                const Divider(color: AppTheme.divider, height: 1),
                ListTile(
                  leading: const Icon(Icons.open_in_new,
                      color: AppTheme.textSecondary, size: 20),
                  title: const Text(
                    '开源许可证',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right,
                      color: AppTheme.textTertiary, size: 18),
                  onTap: () => _showLicenses(),
                ),
              ]),
            ),

            // ── Data Management Section ──
            _buildSectionHeader('数据管理', Icons.storage),
            SliverToBoxAdapter(
              child: _buildSettingCard([
                ListTile(
                  leading: const Icon(Icons.cleaning_services,
                      color: AppTheme.warning, size: 20),
                  title: const Text(
                    '清除缓存',
                    style: TextStyle(fontSize: 14, color: AppTheme.textPrimary),
                  ),
                  subtitle: const Text(
                    '清除临时文件和缓存数据',
                    style:
                        TextStyle(fontSize: 12, color: AppTheme.textTertiary),
                  ),
                  onTap: () => _showClearCacheDialog(),
                ),
                const Divider(color: AppTheme.divider, height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_forever,
                      color: AppTheme.error, size: 20),
                  title: const Text(
                    '重置所有数据',
                    style: TextStyle(fontSize: 14, color: AppTheme.error),
                  ),
                  subtitle: const Text(
                    '删除所有本地数据，此操作不可撤销',
                    style:
                        TextStyle(fontSize: 12, color: AppTheme.textTertiary),
                  ),
                  onTap: () => _showResetDialog(),
                ),
              ]),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppTheme.violetLight),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.violetLight,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingCard(List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GlassCardWidget(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      ),
    );
  }

  Widget _buildToggleSetting({
    required IconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      secondary: Icon(icon, color: AppTheme.textSecondary, size: 20),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          color: AppTheme.textPrimary,
        ),
      ),
      value: value,
      onChanged: onChanged,
      activeColor: AppTheme.violet,
      activeTrackColor: AppTheme.violet.withOpacity(0.3),
      inactiveTrackColor: AppTheme.border,
    );
  }

  Widget _buildSliderSetting({
    required IconData icon,
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.textSecondary, size: 20),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
          ),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.violetLight,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
      subtitle: Slider(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        activeColor: AppTheme.violet,
        inactiveColor: AppTheme.border,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildDropdownSetting({
    required IconData icon,
    required String title,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.textSecondary, size: 20),
      title: Text(
        title,
        style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppTheme.border),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            dropdownColor: AppTheme.surfaceElevated,
            icon: const Icon(Icons.arrow_drop_down,
                size: 18, color: AppTheme.textSecondary),
            style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
            onChanged: onChanged,
            items: items.map((item) {
              return DropdownMenuItem(value: item, child: Text(item));
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildNavigationSetting({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.textSecondary, size: 20),
      title: Text(
        title,
        style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: AppTheme.textTertiary),
      ),
      trailing: const Icon(Icons.chevron_right,
          color: AppTheme.textTertiary, size: 18),
      onTap: onTap,
    );
  }

  Widget _buildAccessibilitySetting() {
    final status = _phoneUseStatus;
    final ready = status?.ready == true;
    final subtitle = _accessibilitySubtitle(status);
    return ListTile(
      key: const ValueKey('settings.accessibility'),
      leading: Icon(
        Icons.accessibility_new_outlined,
        color: ready ? AppTheme.success : AppTheme.textSecondary,
        size: 20,
      ),
      title: const Text(
        '无障碍服务',
        style: TextStyle(fontSize: 14, color: AppTheme.textPrimary),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: AppTheme.textTertiary),
      ),
      trailing: _permissionChecking
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : _PermissionStatePill(
              label: _accessibilityPillLabel(status),
              color: _accessibilityPillColor(status),
            ),
      onTap: _permissionChecking
          ? null
          : () => unawaited(_openAccessibilitySettings()),
      onLongPress: () => unawaited(_refreshPhoneUseStatus()),
    );
  }

  String _accessibilitySubtitle(PhoneUseAccessibilityStatus? status) {
    if (status == null) return '正在检测 PhoneUseAccessibilityService 状态';
    if (!status.supported) return '当前平台不支持 phone-use 无障碍探针';

    final serviceLabel = status.serviceId.isEmpty
        ? 'PhoneUseAccessibilityService'
        : status.serviceId;
    final connection =
        status.serviceConnected ? 'service connected' : 'service disconnected';
    if (status.ready) {
      return '已开启，$connection，可观察窗口；服务：$serviceLabel';
    }
    final reason =
        status.blockedReason == null ? '点击进入系统无障碍设置' : status.blockedReason!;
    return '未开启，$connection；$reason；服务：$serviceLabel';
  }

  String _accessibilityPillLabel(PhoneUseAccessibilityStatus? status) {
    if (status == null) return '检测中';
    if (!status.supported) return '不可用';
    if (status.ready) return '已开启';
    if (status.accessibilityEnabled && !status.serviceConnected) return '待连接';
    if (status.accessibilityEnabled) return '已授权';
    return '未开启';
  }

  Color _accessibilityPillColor(PhoneUseAccessibilityStatus? status) {
    if (status == null || !status.supported) return AppTheme.textTertiary;
    if (status.ready) return AppTheme.success;
    return AppTheme.warning;
  }

  Widget _buildBackgroundPermissionSetting() {
    return ListTile(
      key: const ValueKey('settings.backgroundPermission'),
      leading: const Icon(
        Icons.battery_saver_outlined,
        color: AppTheme.textSecondary,
        size: 20,
      ),
      title: const Text(
        '后台运行权限',
        style: TextStyle(fontSize: 14, color: AppTheme.textPrimary),
      ),
      subtitle: const Text(
        '引导开启应用详情、电池优化和后台保活设置',
        style: TextStyle(fontSize: 12, color: AppTheme.textTertiary),
      ),
      trailing: const Icon(
        Icons.chevron_right,
        color: AppTheme.textTertiary,
        size: 18,
      ),
      onTap: _showBackgroundPermissionGuide,
    );
  }

  Future<void> _refreshPhoneUseStatus() async {
    if (_permissionChecking) return;
    setState(() => _permissionChecking = true);
    final status = await PhoneUseAccessibilityService.instance.getStatus();
    if (!mounted) return;
    setState(() {
      _phoneUseStatus = status;
      _permissionChecking = false;
    });
  }

  Future<void> _openAccessibilitySettings() async {
    final opened =
        await PhoneUseAccessibilityService.instance.openAccessibilitySettings();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(opened ? '已打开系统无障碍设置' : '无法打开无障碍设置')),
    );
    await _refreshPhoneUseStatus();
  }

  Future<void> _openAppSettings() async {
    final opened =
        await PhoneUseAccessibilityService.instance.openAppSettings();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(opened ? '已打开应用详情' : '无法打开应用详情')),
    );
  }

  Future<void> _openBatteryOptimizationSettings() async {
    final opened = await PhoneUseAccessibilityService.instance
        .openBatteryOptimizationSettings();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(opened ? '已打开电池优化设置' : '无法打开电池优化设置')),
    );
  }

  void _showBackgroundPermissionGuide() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Text(
                  '后台运行权限',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '用于保持 MobileCode Helper 和长任务状态稳定。不同 Android 厂商设置名称不同，开启后请回到 MobileCode 刷新 runtime 状态。',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          unawaited(_openAppSettings());
                        },
                        icon: const Icon(Icons.settings_applications_outlined),
                        label: const Text('应用详情'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          unawaited(_openBatteryOptimizationSettings());
                        },
                        icon: const Icon(Icons.battery_charging_full_outlined),
                        label: const Text('电池设置'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildThemeSelector() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: _ThemeOption(
              icon: Icons.dark_mode,
              label: '深色',
              isSelected: _themeMode == 'dark',
              onTap: () => setState(() => _themeMode = 'dark'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ThemeOption(
              icon: Icons.light_mode,
              label: '浅色',
              isSelected: _themeMode == 'light',
              onTap: () => setState(() => _themeMode = 'light'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ThemeOption(
              icon: Icons.brightness_auto,
              label: '系统',
              isSelected: _themeMode == 'system',
              onTap: () => setState(() => _themeMode = 'system'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
              fontFamily: AppTheme.fontCode,
            ),
          ),
        ],
      ),
    );
  }

  void _showDisconnectDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        title: const Text('断开 GitHub',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text(
          '确定要断开 GitHub 连接吗？',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _githubConnected = false;
                _githubUsername = null;
              });
              Navigator.pop(context);
            },
            child: const Text('断开', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
  }

  void _showClearCacheDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        title:
            const Text('清除缓存', style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text(
          '确定要清除缓存吗？这不会影响你的项目或设置。',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('缓存已清除')),
              );
            },
            child: const Text('清除', style: TextStyle(color: AppTheme.warning)),
          ),
        ],
      ),
    );
  }

  void _showResetDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        title: const Text('重置所有数据', style: TextStyle(color: AppTheme.error)),
        content: const Text(
          '警告：此操作将删除所有本地数据，包括项目、代码片段和设置。此操作不可撤销！',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('所有数据已重置')),
              );
            },
            child: const Text('确认重置', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
  }

  void _showLicenses() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        title:
            const Text('开源许可证', style: TextStyle(color: AppTheme.textPrimary)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: const [
              ListTile(
                title: Text('Flutter',
                    style: TextStyle(color: AppTheme.textPrimary)),
                subtitle: Text('BSD 3-Clause License',
                    style: TextStyle(color: AppTheme.textSecondary)),
              ),
              ListTile(
                title: Text('Material Design',
                    style: TextStyle(color: AppTheme.textPrimary)),
                subtitle: Text('Apache 2.0',
                    style: TextStyle(color: AppTheme.textSecondary)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭', style: TextStyle(color: AppTheme.cyan)),
          ),
        ],
      ),
    );
  }
}

class _PermissionStatePill extends StatelessWidget {
  const _PermissionStatePill({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ── Theme Option Widget ──
class _ThemeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.violet.withOpacity(0.15)
              : AppTheme.surfaceDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.violet : AppTheme.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? AppTheme.violetLight : AppTheme.textTertiary,
              size: 24,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color:
                    isSelected ? AppTheme.violetLight : AppTheme.textSecondary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
