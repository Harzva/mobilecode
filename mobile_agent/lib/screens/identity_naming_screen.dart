import 'package:flutter/material.dart';

import '../services/identity_naming_service.dart';
import '../themes/app_theme.dart';
import '../widgets/glass_card_widget.dart';

class IdentityNamingScreen extends StatefulWidget {
  IdentityNamingScreen({
    super.key,
    IdentityNamingService? service,
  }) : service = service ?? IdentityNamingService();

  final IdentityNamingService service;

  @override
  State<IdentityNamingScreen> createState() => _IdentityNamingScreenState();
}

class _IdentityNamingScreenState extends State<IdentityNamingScreen> {
  final _userController = TextEditingController();
  final _mobileCodeController = TextEditingController();
  final _assistantController = TextEditingController();
  IdentityNamingPreferences _preferences = const IdentityNamingPreferences();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _userController.dispose();
    _mobileCodeController.dispose();
    _assistantController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final preferences = await widget.service.load();
    if (!mounted) return;
    setState(() {
      _preferences = preferences;
      _userController.text = preferences.userDisplayName;
      _mobileCodeController.text = preferences.mobileCodeNickname;
      _assistantController.text = preferences.assistantPersonaLabel;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final next = _preferences.copyWith(
      userDisplayName: _userController.text,
      mobileCodeNickname: _mobileCodeController.text,
      assistantPersonaLabel: _assistantController.text,
    );
    await widget.service.save(next);
    if (!mounted) return;
    setState(() {
      _preferences = next;
      _saving = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Identity 已保存到本地')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.deepSpace,
      appBar: AppBar(
        title: const Text('Identity'),
        backgroundColor: AppTheme.deepSpace,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.border.withOpacity(0.7),
                    ),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.badge_outlined, color: AppTheme.cyan),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Local Identity',
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              '本地保存称呼偏好，用于后续上下文注入；不写入公开日志、截图素材或远端 telemetry。',
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                GlassCardWidget(
                  borderRadius: 12,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const _IdentityHintRow(
                          icon: Icons.person_outline,
                          title: '怎么称呼你',
                          subtitle: '用户希望 MobileCode 如何称呼自己',
                        ),
                        const SizedBox(height: 10),
                        _field(
                          controller: _userController,
                          label: '用户称呼',
                          hint: '例如：Harzva',
                        ),
                        const SizedBox(height: 16),
                        const _IdentityHintRow(
                          icon: Icons.phone_android_outlined,
                          title: 'App 的昵称',
                          subtitle: '用户给这个 App / Agent 的本地昵称',
                        ),
                        const SizedBox(height: 10),
                        _field(
                          controller: _mobileCodeController,
                          label: 'MobileCode 昵称',
                          hint: 'MobileCode',
                        ),
                        const SizedBox(height: 16),
                        const _IdentityHintRow(
                          icon: Icons.auto_awesome_outlined,
                          title: 'Assistant 标签',
                          subtitle: '模型自称标签，只作为本地上下文提示',
                        ),
                        const SizedBox(height: 10),
                        _field(
                          controller: _assistantController,
                          label: 'Assistant self-name',
                          hint: 'Codex',
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            key: const ValueKey('identity.save'),
                            onPressed: _saving ? null : _save,
                            icon: _saving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: const Text('保存'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                GlassCardWidget(
                  borderRadius: 12,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.integration_instructions_outlined,
                              color: AppTheme.cyan,
                              size: 20,
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Context Preview',
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.deepSpace.withOpacity(0.62),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppTheme.border.withOpacity(0.5),
                            ),
                          ),
                          child: Text(
                            _preferences
                                .copyWith(
                                  userDisplayName: _userController.text,
                                  mobileCodeNickname:
                                      _mobileCodeController.text,
                                  assistantPersonaLabel:
                                      _assistantController.text,
                                )
                                .compactContextBlock(),
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontFamily: AppTheme.fontCode,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
  }) {
    return TextField(
      controller: controller,
      maxLength: 48,
      style: const TextStyle(color: AppTheme.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        counterText: '',
        labelStyle: const TextStyle(color: AppTheme.textSecondary),
        hintStyle: const TextStyle(color: AppTheme.textTertiary),
        enabledBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: AppTheme.border),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: AppTheme.cyan),
        ),
      ),
    );
  }
}

class _IdentityHintRow extends StatelessWidget {
  const _IdentityHintRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppTheme.cyan, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppTheme.textTertiary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
