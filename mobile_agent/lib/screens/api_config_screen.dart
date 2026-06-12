import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../themes/app_theme.dart';

/// LLM provider configuration shared with HomeScreen.
///
/// This screen intentionally writes the same SharedPreferences keys that the
/// chat surface reads, so Settings, drawer shortcuts, and the chat composer do
/// not drift into separate provider profiles.
class ApiConfigScreen extends StatefulWidget {
  const ApiConfigScreen({super.key});

  @override
  State<ApiConfigScreen> createState() => _ApiConfigScreenState();
}

enum _ProviderPreset { mimo, deepSeek, anthropic, openAi, custom }

class _ProviderDefinition {
  const _ProviderDefinition({
    required this.preset,
    required this.label,
    required this.baseUrl,
    required this.model,
    required this.icon,
  });

  final _ProviderPreset preset;
  final String label;
  final String baseUrl;
  final String model;
  final IconData icon;
}

class _ApiConfigScreenState extends State<ApiConfigScreen> {
  static const _baseUrlKey = 'mobilecode.baseUrl';
  static const _apiKeyKey = 'mobilecode.apiKey';
  static const _modelKey = 'mobilecode.model';
  static const _providerModeKey = 'mobilecode.providerMode';
  static const _managedProviderPresetKey = 'mobilecode.managedProviderPreset';
  static const _deepSeekInviteAcceptedKey = 'mobilecode.deepseekDevInviteAccepted';
  static const _defaultBaseUrl = 'https://token-plan-cn.xiaomimimo.com/anthropic';
  static const _defaultModel = 'mimo-v2.5-pro';
  static const _deepSeekInviteCode = String.fromEnvironment(
    'MOBILECODE_DEEPSEEK_DEV_INVITE',
    defaultValue: 'asdfg',
  );
  static const _managedRelayUrl = String.fromEnvironment('MOBILECODE_MANAGED_RELAY_URL');
  static const _managedDeepSeekProviderEnabled = bool.fromEnvironment('MOBILECODE_MANAGED_DEEPSEEK_PROVIDER');
  static const _managedDeepSeekBaseUrl = String.fromEnvironment(
    'MOBILECODE_MANAGED_DEEPSEEK_BASE_URL',
    defaultValue: 'https://api.deepseek.com',
  );
  static const _managedDeepSeekModel = String.fromEnvironment(
    'MOBILECODE_MANAGED_DEEPSEEK_MODEL',
    defaultValue: 'deepseek-v4-flash',
  );

  static const _providers = [
    _ProviderDefinition(
      preset: _ProviderPreset.mimo,
      label: 'Mimo Anthropic',
      baseUrl: _defaultBaseUrl,
      model: _defaultModel,
      icon: Icons.auto_awesome_outlined,
    ),
    _ProviderDefinition(
      preset: _ProviderPreset.deepSeek,
      label: 'DeepSeek v4 Flash',
      baseUrl: _managedDeepSeekBaseUrl,
      model: _managedDeepSeekModel,
      icon: Icons.psychology_alt_outlined,
    ),
    _ProviderDefinition(
      preset: _ProviderPreset.anthropic,
      label: 'Anthropic',
      baseUrl: 'https://api.anthropic.com',
      model: 'claude-3-5-sonnet-latest',
      icon: Icons.hub_outlined,
    ),
    _ProviderDefinition(
      preset: _ProviderPreset.openAi,
      label: 'OpenAI',
      baseUrl: 'https://api.openai.com/v1',
      model: 'gpt-4o-mini',
      icon: Icons.api_outlined,
    ),
    _ProviderDefinition(
      preset: _ProviderPreset.custom,
      label: 'Custom Provider',
      baseUrl: '',
      model: '',
      icon: Icons.tune_outlined,
    ),
  ];

  final _baseUrlController = TextEditingController(text: _defaultBaseUrl);
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController(text: _defaultModel);
  final _inviteController = TextEditingController();
  _ProviderPreset _selectedPreset = _ProviderPreset.mimo;
  bool _deepSeekInviteAccepted = false;
  bool _loading = true;
  bool _saving = false;

  bool get _deepSeekSelected => _selectedPreset == _ProviderPreset.deepSeek;
  bool get _deepSeekRelayAvailable => _managedDeepSeekProviderEnabled && _managedRelayUrl.trim().isNotEmpty;

  String get _normalizedManagedRelayUrl {
    final relay = _managedRelayUrl.trim();
    if (relay.endsWith('/')) return relay.substring(0, relay.length - 1);
    return relay;
  }

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    _inviteController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = prefs.getString(_baseUrlKey)?.trim();
    final model = prefs.getString(_modelKey)?.trim();
    if (!mounted) return;
    setState(() {
      _baseUrlController.text = baseUrl == null || baseUrl.isEmpty ? _defaultBaseUrl : baseUrl;
      _apiKeyController.text = prefs.getString(_apiKeyKey) ?? '';
      _modelController.text = model == null || model.isEmpty ? _defaultModel : model;
      _selectedPreset = _detectPreset(_baseUrlController.text, _modelController.text);
      _deepSeekInviteAccepted = prefs.getBool(_deepSeekInviteAcceptedKey) ?? false;
      _loading = false;
    });
  }

  _ProviderPreset _detectPreset(String baseUrl, String model) {
    final probe = '$baseUrl $model'.toLowerCase();
    if (probe.contains('xiaomimimo') || probe.contains('mimo-')) {
      return _ProviderPreset.mimo;
    }
    if (probe.contains('deepseek')) {
      return _ProviderPreset.deepSeek;
    }
    if (probe.contains('anthropic') || probe.contains('claude')) {
      return _ProviderPreset.anthropic;
    }
    if (probe.contains('openai') || probe.contains('gpt-')) {
      return _ProviderPreset.openAi;
    }
    return _ProviderPreset.custom;
  }

  void _selectPreset(_ProviderDefinition provider) {
    setState(() {
      _selectedPreset = provider.preset;
      if (provider.preset == _ProviderPreset.deepSeek && _deepSeekInviteAccepted && _deepSeekRelayAvailable) {
        _baseUrlController.text = _normalizedManagedRelayUrl;
        _apiKeyController.text = 'invite:$_deepSeekInviteCode';
      } else if (provider.baseUrl.isNotEmpty) {
        _baseUrlController.text = provider.baseUrl;
      }
      if (provider.model.isNotEmpty) {
        _modelController.text = provider.model;
      }
    });
  }

  Future<void> _unlockDeepSeekDevAccess() async {
    final invite = _inviteController.text.trim();
    if (invite != _deepSeekInviteCode) {
      _showMessage('邀请码不正确');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_deepSeekInviteAcceptedKey, true);
    if (!mounted) return;

    setState(() {
      _deepSeekInviteAccepted = true;
      _selectedPreset = _ProviderPreset.deepSeek;
      _modelController.text = _managedDeepSeekModel;
      if (_deepSeekRelayAvailable) {
        _baseUrlController.text = _normalizedManagedRelayUrl;
        _apiKeyController.text = 'invite:$invite';
      } else {
        _baseUrlController.text = _managedDeepSeekBaseUrl;
        _apiKeyController.clear();
      }
    });

    _showMessage(
      _deepSeekRelayAvailable
          ? 'DeepSeek 测试 relay 已解锁，请保存配置'
          : 'DeepSeek preset 已解锁；未配置 relay，请输入自己的 DeepSeek API Key',
    );
  }

  void _useDeepSeekOfficialKeyMode() {
    setState(() {
      _selectedPreset = _ProviderPreset.deepSeek;
      _baseUrlController.text = _managedDeepSeekBaseUrl;
      _modelController.text = _managedDeepSeekModel;
      if (_apiKeyController.text.trim().startsWith('invite:')) {
        _apiKeyController.clear();
      }
    });
  }

  void _useDeepSeekRelayMode() {
    if (!_deepSeekRelayAvailable) {
      _showMessage('当前构建未配置 MOBILECODE_MANAGED_RELAY_URL');
      return;
    }
    if (!_deepSeekInviteAccepted) {
      _showMessage('请先输入邀请码');
      return;
    }
    setState(() {
      _selectedPreset = _ProviderPreset.deepSeek;
      _baseUrlController.text = _normalizedManagedRelayUrl;
      _modelController.text = _managedDeepSeekModel;
      _apiKeyController.text = 'invite:$_deepSeekInviteCode';
    });
  }

  Future<void> _save() async {
    final baseUrl = _baseUrlController.text.trim();
    final model = _modelController.text.trim();
    if (baseUrl.isEmpty || model.isEmpty) {
      _showMessage('请填写 Base URL 和 Model');
      return;
    }
    final uri = Uri.tryParse(baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      _showMessage('Base URL 格式不正确');
      return;
    }
    final usesDeepSeekManagedRelay = _selectedPreset == _ProviderPreset.deepSeek &&
        _deepSeekInviteAccepted &&
        _deepSeekRelayAvailable &&
        baseUrl == _normalizedManagedRelayUrl;
    if (_selectedPreset == _ProviderPreset.deepSeek &&
        !usesDeepSeekManagedRelay &&
        _apiKeyController.text.trim().isEmpty) {
      _showMessage('未使用 DeepSeek managed relay 时，需要输入自己的 DeepSeek API Key');
      return;
    }

    setState(() => _saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (usesDeepSeekManagedRelay) {
        await prefs.setString(_providerModeKey, 'managed');
        await prefs.setString(_managedProviderPresetKey, _ProviderPreset.deepSeek.name);
        await prefs.setBool(_deepSeekInviteAcceptedKey, true);
        if (!mounted) return;
        _showMessage('DeepSeek managed relay 已保存');
        Navigator.of(context).maybePop();
        return;
      }

      await prefs.setString(_providerModeKey, 'custom');
      await prefs.setString(_baseUrlKey, baseUrl);
      await prefs.setString(_apiKeyKey, _apiKeyController.text.trim());
      await prefs.setString(_modelKey, model);
      if (!mounted) return;
      _showMessage('模型配置已保存');
      Navigator.of(context).maybePop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.auroraBackground,
      appBar: AppBar(
        title: const Text('模型与 Provider'),
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Provider',
                          style: TextStyle(
                            color: AppTheme.auroraText,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final provider in _providers)
                              ChoiceChip(
                                avatar: Icon(provider.icon, size: 16),
                                label: Text(provider.label),
                                selected: _selectedPreset == provider.preset,
                                onSelected: (_) => _selectPreset(provider),
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _baseUrlController,
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Base URL',
                            hintText: 'https://api.example.com/v1',
                            prefixIcon: Icon(Icons.link_outlined),
                          ),
                          onChanged: (_) => setState(() {
                            _selectedPreset = _detectPreset(_baseUrlController.text, _modelController.text);
                          }),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _modelController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Model',
                            hintText: 'mimo-v2.5-pro / deepseek-v4-flash / gpt-4o-mini',
                            prefixIcon: Icon(Icons.memory_outlined),
                          ),
                          onChanged: (_) => setState(() {
                            _selectedPreset = _detectPreset(_baseUrlController.text, _modelController.text);
                          }),
                        ),
                        if (_deepSeekSelected) ...[
                          const SizedBox(height: 12),
                          _DeepSeekDevAccessCard(
                            inviteController: _inviteController,
                            unlocked: _deepSeekInviteAccepted,
                            relayAvailable: _deepSeekRelayAvailable,
                            relayUrl: _normalizedManagedRelayUrl,
                            onUnlock: _unlockDeepSeekDevAccess,
                            onUseRelay: _useDeepSeekRelayMode,
                            onUseOwnKey: _useDeepSeekOfficialKeyMode,
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextField(
                          controller: _apiKeyController,
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            labelText: 'API Key',
                            hintText: 'sk-... or provider token',
                            prefixIcon: Icon(Icons.key_outlined),
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'DeepSeek v4 Flash 是默认体验配置；邀请码只解锁测试入口，不保护内置密钥。真实 DeepSeek key 不应写进 APK/IPA，免费测试应走 relay。',
                          style: TextStyle(color: AppTheme.auroraTextMuted, fontSize: 12, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Saving' : 'Save provider'),
                ),
              ],
            ),
    );
  }
}

class _DeepSeekDevAccessCard extends StatelessWidget {
  const _DeepSeekDevAccessCard({
    required this.inviteController,
    required this.unlocked,
    required this.relayAvailable,
    required this.relayUrl,
    required this.onUnlock,
    required this.onUseRelay,
    required this.onUseOwnKey,
  });

  final TextEditingController inviteController;
  final bool unlocked;
  final bool relayAvailable;
  final String relayUrl;
  final VoidCallback onUnlock;
  final VoidCallback onUseRelay;
  final VoidCallback onUseOwnKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.auroraSurface.withOpacity(0.78),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.auroraViolet.withOpacity(0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                unlocked ? Icons.lock_open_outlined : Icons.lock_outline,
                color: unlocked ? AppTheme.success : AppTheme.auroraViolet,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'DeepSeek Dev Invite',
                  style: TextStyle(
                    color: AppTheme.auroraText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '邀请码只解锁测试入口。App 不内置真实 DeepSeek API Key；免费测试应由 relay 在服务端持有密钥。',
            style: TextStyle(
              color: AppTheme.auroraTextMuted,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          if (!unlocked) ...[
            TextField(
              controller: inviteController,
              obscureText: true,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Invite code',
                hintText: '输入测试邀请码',
                prefixIcon: Icon(Icons.password_outlined),
              ),
              onSubmitted: (_) => onUnlock(),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: onUnlock,
              icon: const Icon(Icons.key_outlined),
              label: const Text('Unlock DeepSeek test'),
            ),
          ] else ...[
            _DeepSeekDevStatusRow(
              icon: Icons.check_circle_outline,
              text: relayAvailable
                  ? '已解锁。当前构建配置了 relay，可保存后使用测试通道。'
                  : '已解锁，但当前构建没有 relay；请填写自己的 DeepSeek API Key。',
              color: relayAvailable ? AppTheme.success : AppTheme.warning,
            ),
            if (relayAvailable) ...[
              const SizedBox(height: 8),
              _DeepSeekDevStatusRow(
                icon: Icons.route_outlined,
                text: relayUrl,
                color: AppTheme.auroraViolet,
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: relayAvailable ? onUseRelay : null,
                  icon: const Icon(Icons.cloud_sync_outlined),
                  label: const Text('Use relay'),
                ),
                OutlinedButton.icon(
                  onPressed: onUseOwnKey,
                  icon: const Icon(Icons.key_outlined),
                  label: const Text('Use own key'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DeepSeekDevStatusRow extends StatelessWidget {
  const _DeepSeekDevStatusRow({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppTheme.auroraTextMuted,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}
