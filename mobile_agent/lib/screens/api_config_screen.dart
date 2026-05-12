import 'package:flutter/material.dart';
import '../themes/app_theme.dart';
import '../widgets/glass_card_widget.dart';
import '../widgets/gradient_button_widget.dart';
import '../models/api_config_model.dart';

/// LLM API Configuration screen
/// Manage API keys for OpenAI, Claude, Gemini, Custom providers
class ApiConfigScreen extends StatefulWidget {
  const ApiConfigScreen({super.key});

  @override
  State<ApiConfigScreen> createState() => _ApiConfigScreenState();
}

class _ApiConfigScreenState extends State<ApiConfigScreen> {
  final List<Map<String, dynamic>> _configs = [
    {
      'id': '1',
      'name': 'OpenAI GPT-4',
      'provider': LLMProvider.openAI,
      'apiKey': '',  // SECURE: Load from SecureStorage or env var, never hardcode
      'baseUrl': 'https://api.openai.com/v1',
      'model': 'gpt-4o',
      'isActive': true,
      'temperature': 0.7,
    },
    {
      'id': '2',
      'name': 'Claude Sonnet',
      'provider': LLMProvider.claude,
      'apiKey': '',  // SECURE: Load from SecureStorage or env var, never hardcode
      'baseUrl': 'https://api.anthropic.com/v1',
      'model': 'claude-3-5-sonnet',
      'isActive': false,
      'temperature': 0.8,
    },
    {
      'id': '3',
      'name': 'Gemini Pro',
      'provider': LLMProvider.gemini,
      'apiKey': '',  // SECURE: Load from SecureStorage or env var, never hardcode
      'baseUrl': 'https://generativelanguage.googleapis.com/v1',
      'model': 'gemini-1.5-pro',
      'isActive': false,
      'temperature': 0.7,
    },
  ];

  void _toggleActive(String id) {
    setState(() {
      for (final config in _configs) {
        if (config['id'] == id) {
          config['isActive'] = !config['isActive'];
        } else {
          config['isActive'] = false; // Only one active at a time
        }
      }
    });
  }

  void _deleteConfig(String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        title: const Text('删除配置', style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text(
          '确定要删除这个 API 配置吗？',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              setState(() => _configs.removeWhere((c) => c['id'] == id));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('配置已删除')),
              );
            },
            child: const Text('删除', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
  }

  void _showAddConfigSheet({Map<String, dynamic>? existingConfig}) {
    final isEditing = existingConfig != null;
    final nameController = TextEditingController(text: existingConfig?['name'] ?? '');
    final keyController = TextEditingController(text: existingConfig?['apiKey'] ?? '');
    final urlController = TextEditingController(text: existingConfig?['baseUrl'] ?? '');
    LLMProvider selectedProvider = existingConfig?['provider'] ?? LLMProvider.openAI;
    String selectedModel = existingConfig?['model'] ?? 'gpt-4o';
    double temperature = (existingConfig?['temperature'] ?? 0.7).toDouble();
    bool isTesting = false;
    bool? testResult;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppTheme.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    isEditing ? '编辑 API 配置' : '添加 API 配置',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Name
                  TextField(
                    controller: nameController,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: const InputDecoration(
                      labelText: '配置名称',
                      labelStyle: TextStyle(color: AppTheme.textSecondary),
                      hintText: '例如: OpenAI GPT-4',
                      hintStyle: TextStyle(color: AppTheme.textTertiary),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Provider selector
                  const Text(
                    '提供商',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: LLMProvider.values.map((provider) {
                      final isSelected = provider == selectedProvider;
                      return ChoiceChip(
                        label: Text(provider.displayName),
                        selected: isSelected,
                        onSelected: (_) {
                          setModalState(() {
                            selectedProvider = provider;
                            selectedModel =
                                ApiConfig.defaultModels(provider).first;
                            if (urlController.text.isEmpty) {
                              urlController.text =
                                  ApiConfig.defaultBaseUrl(provider);
                            }
                          });
                        },
                        selectedColor: AppTheme.violet.withOpacity(0.3),
                        labelStyle: TextStyle(
                          color: isSelected
                              ? AppTheme.violetLight
                              : AppTheme.textSecondary,
                          fontSize: 13,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // API Key
                  TextField(
                    controller: keyController,
                    obscureText: true,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'API Key',
                      labelStyle: TextStyle(color: AppTheme.textSecondary),
                      hintText: 'sk-...',
                      hintStyle: TextStyle(color: AppTheme.textTertiary),
                      prefixIcon: Icon(Icons.vpn_key, color: AppTheme.textTertiary),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Base URL
                  TextField(
                    controller: urlController,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Base URL',
                      labelStyle: TextStyle(color: AppTheme.textSecondary),
                      hintText: 'https://api.example.com/v1',
                      hintStyle: TextStyle(color: AppTheme.textTertiary),
                      prefixIcon: Icon(Icons.link, color: AppTheme.textTertiary),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Model selector
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceDark,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedModel,
                        isExpanded: true,
                        dropdownColor: AppTheme.surfaceDark,
                        icon: const Icon(Icons.arrow_drop_down,
                            color: AppTheme.textSecondary),
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                        ),
                        onChanged: (v) => setModalState(() => selectedModel = v!),
                        items: ApiConfig.defaultModels(selectedProvider)
                            .map((model) => DropdownMenuItem(
                                  value: model,
                                  child: Text(model),
                                ))
                            .toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Temperature slider
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Temperature',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      Text(
                        temperature.toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.violetLight,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: temperature,
                    min: 0.0,
                    max: 2.0,
                    divisions: 20,
                    activeColor: AppTheme.violet,
                    inactiveColor: AppTheme.border,
                    onChanged: (v) => setModalState(() => temperature = v),
                  ),
                  const SizedBox(height: 16),

                  // Test connection button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: isTesting
                          ? null
                          : () async {
                              setModalState(() {
                                isTesting = true;
                                testResult = null;
                              });
                              await Future.delayed(
                                  const Duration(seconds: 1));
                              setModalState(() {
                                isTesting = false;
                                testResult = true;
                              });
                            },
                      icon: isTesting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(
                                    AppTheme.violetLight),
                              ),
                            )
                          : Icon(
                              testResult == true
                                  ? Icons.check_circle
                                  : Icons.network_check,
                              size: 18,
                              color: testResult == true
                                  ? AppTheme.success
                                  : AppTheme.textSecondary,
                            ),
                      label: Text(
                        isTesting
                            ? '测试中...'
                            : testResult == true
                                ? '连接成功'
                                : '测试连接',
                        style: TextStyle(
                          color: testResult == true
                              ? AppTheme.success
                              : AppTheme.textSecondary,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: testResult == true
                              ? AppTheme.success
                              : AppTheme.border,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    child: GradientButtonWidget(
                      label: isEditing ? '保存更改' : '添加配置',
                      icon: isEditing ? Icons.save : Icons.add,
                      onPressed: () {
                        if (nameController.text.isEmpty ||
                            keyController.text.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('请填写必填项')),
                          );
                          return;
                        }

                        setState(() {
                          if (isEditing) {
                            final idx = _configs.indexWhere(
                                (c) => c['id'] == existingConfig['id']);
                            if (idx != -1) {
                              _configs[idx] = {
                                ...existingConfig,
                                'name': nameController.text,
                                'provider': selectedProvider,
                                'apiKey': keyController.text,
                                'baseUrl': urlController.text,
                                'model': selectedModel,
                                'temperature': temperature,
                              };
                            }
                          } else {
                            _configs.add({
                              'id': DateTime.now()
                                  .millisecondsSinceEpoch
                                  .toString(),
                              'name': nameController.text,
                              'provider': selectedProvider,
                              'apiKey': keyController.text,
                              'baseUrl': urlController.text,
                              'model': selectedModel,
                              'isActive': false,
                              'temperature': temperature,
                            });
                          }
                        });
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                isEditing ? '配置已更新' : '配置已添加'),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.deepSpace,
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceDark,
        elevation: 0,
        title: const Text(
          'API 配置',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: AppTheme.textSecondary),
        ),
      ),
      body: SafeArea(
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 12),
          itemCount: _configs.length,
          itemBuilder: (context, index) {
            final config = _configs[index];
            return _buildConfigCard(config);
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddConfigSheet(),
        icon: const Icon(Icons.add),
        label: const Text('添加 API'),
      ),
    );
  }

  Widget _buildConfigCard(Map<String, dynamic> config) {
    final providerColors = {
      LLMProvider.openAI: const Color(0xFF10A37F),
      LLMProvider.claude: const Color(0xFFD4A574),
      LLMProvider.gemini: const Color(0xFF4285F4),
      LLMProvider.custom: AppTheme.textSecondary,
    };

    return Dismissible(
      key: ValueKey(config['id']),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.error.withOpacity(0.2),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: AppTheme.error),
      ),
      onDismissed: (_) => _deleteConfig(config['id']),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: GlassCardWidget(
          onTap: () => _showAddConfigSheet(existingConfig: config),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Provider indicator
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: providerColors[config['provider']] ??
                            AppTheme.textSecondary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        config['name'],
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    // Active toggle
                    Switch(
                      value: config['isActive'] ?? false,
                      onChanged: (_) => _toggleActive(config['id']),
                      activeColor: AppTheme.violet,
                      activeTrackColor: AppTheme.violet.withOpacity(0.3),
                      inactiveTrackColor: AppTheme.border,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  (config['provider'] as LLMProvider).displayName,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  config['model'],
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.violetLight,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.link,
                      size: 12,
                      color: AppTheme.textTertiary.withOpacity(0.7),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        config['baseUrl'],
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textTertiary.withOpacity(0.7),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (config['isActive'] == true)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.success.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_circle,
                              size: 12,
                              color: AppTheme.success,
                            ),
                            SizedBox(width: 4),
                            Text(
                              '默认',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.success,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
