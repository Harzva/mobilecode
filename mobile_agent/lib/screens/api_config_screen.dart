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
  static const _defaultBaseUrl = 'https://token-plan-cn.xiaomimimo.com/anthropic';
  static const _defaultModel = 'mimo-v2.5-pro';

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
      label: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com/v1',
      model: 'deepseek-chat',
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
  _ProviderPreset _selectedPreset = _ProviderPreset.mimo;
  bool _loading = true;
  bool _saving = false;

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
      if (provider.baseUrl.isNotEmpty) {
        _baseUrlController.text = provider.baseUrl;
      }
      if (provider.model.isNotEmpty) {
        _modelController.text = provider.model;
      }
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

    setState(() => _saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
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
                            hintText: 'mimo-v2.5-pro / gpt-4o-mini / claude-3-5-sonnet-latest',
                            prefixIcon: Icon(Icons.memory_outlined),
                          ),
                          onChanged: (_) => setState(() {
                            _selectedPreset = _detectPreset(_baseUrlController.text, _modelController.text);
                          }),
                        ),
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
                          'DeepSeek 使用 OpenAI-compatible 调用路径；/beta Base URL 可用于后续 strict tool calling 验证。保存后 Home/Chat 会立即读取同一份配置。',
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
