import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/theme.dart';
import '../services/role_library_service.dart';

const _roleAvatarChoices = [
  'assets/role_avatars/avatar-batch2-01-mist-studio.svg',
  'assets/role_avatars/avatar-batch2-02-office-glasses.svg',
  'assets/role_avatars/avatar-batch2-09-blue-cap.svg',
  'assets/role_avatars/avatar-batch2-15-tech.svg',
  'assets/role_avatars/avatar-batch2-18-pencil-wash.svg',
  'assets/role_avatars/avatar-batch2-21-navy.svg',
  'assets/role_avatars/avatar-batch2-23-mono.svg',
  'assets/role_avatars/avatar-batch2-24-rounded-icon.svg',
  'assets/role_avatars/avatar-batch2-35-yellow-bucket.svg',
];

const _roleColorChoices = [
  0xFF7557E8,
  0xFF2555FF,
  0xFF16B9C7,
  0xFF0B9B7E,
  0xFFB7791F,
  0xFFE0526E,
  0xFF4F8F2D,
  0xFF0B1020,
];

class RoleManagerScreen extends StatefulWidget {
  const RoleManagerScreen({
    super.key,
    this.onPolishRoleIntent,
  });

  final Future<String> Function(String intent)? onPolishRoleIntent;

  @override
  State<RoleManagerScreen> createState() => _RoleManagerScreenState();
}

class _RoleManagerScreenState extends State<RoleManagerScreen> {
  final _service = RoleLibraryService.instance;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _service.addListener(_handleRoleLibraryChanged);
    _load();
  }

  @override
  void dispose() {
    _service.removeListener(_handleRoleLibraryChanged);
    super.dispose();
  }

  Future<void> _load() async {
    await _service.initialize();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  void _handleRoleLibraryChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _openEditor([MobileCodeRole? role]) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (context) => _RoleEditorSheet(
        initialRole: role,
        onPolishRoleIntent: widget.onPolishRoleIntent,
        onSave: (nextRole) async {
          await _service.upsertCustomRole(nextRole);
          if (mounted) {
            ScaffoldMessenger.of(this.context).showSnackBar(const SnackBar(content: Text('Role saved')));
          }
        },
      ),
    );
  }

  Future<void> _removeRole(MobileCodeRole role) async {
    await _service.removeCustomRole(role.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${role.name} removed')));
  }

  @override
  Widget build(BuildContext context) {
    final roles = _service.allRoles;
    final enabled = _service.enabledRoles.length;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background.withOpacity(0.92),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Roles',
          style: TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: AppTheme.textSecondary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            tooltip: 'Add custom role',
            icon: const Icon(Icons.add_circle_outline, color: AppTheme.primary),
            onPressed: () => _openEditor(),
          ),
          const SizedBox(width: 6),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primary,
        foregroundColor: AppTheme.textOnPrimary,
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('自定义角色'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                _RoleLibraryHeader(total: roles.length, enabled: enabled),
                const SizedBox(height: 12),
                for (final role in roles) ...[
                  _RoleCard(
                    role: role,
                    onToggle: (value) => _service.setRoleEnabled(role.id, value),
                    onEdit: role.builtIn ? null : () => _openEditor(role),
                    onDelete: role.builtIn ? null : () => _removeRole(role),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
    );
  }
}

class _RoleLibraryHeader extends StatelessWidget {
  const _RoleLibraryHeader({
    required this.total,
    required this.enabled,
  });

  final int total;
  final int enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.groups_2_outlined, color: AppTheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Role Recruit library',
                      style: TextStyle(
                        fontFamily: AppTheme.fontBody,
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '$enabled enabled / $total roles',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'RR mode uses these roles as personalities and responsibilities inside one execution lane. It is not a parallel multi-agent scheduler.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.role,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final MobileCodeRole role;
  final ValueChanged<bool> onToggle;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final color = Color(role.colorValue);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: role.enabled ? color.withOpacity(0.35) : AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _RoleAvatar(asset: role.avatarAsset, color: color, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            role.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: AppTheme.fontBody,
                              color: AppTheme.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            role.builtIn ? 'built-in' : 'custom',
                            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      role.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.3),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(value: role.enabled, onChanged: onToggle),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            role.mission,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final item in role.responsibilities.take(3))
                _RoleChip(label: item, color: color),
            ],
          ),
          if (onEdit != null || onDelete != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (onEdit != null)
                  OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('编辑'),
                  ),
                if (onEdit != null && onDelete != null) const SizedBox(width: 8),
                if (onDelete != null)
                  OutlinedButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('删除'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _RoleAvatar extends StatelessWidget {
  const _RoleAvatar({
    required this.asset,
    required this.color,
    required this.size,
  });

  final String asset;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.24)),
      ),
      child: SvgPicture.asset(
        asset,
        fit: BoxFit.contain,
        placeholderBuilder: (_) => Icon(Icons.person_outline, color: color),
      ),
    );
  }
}

class _RoleEditorSheet extends StatefulWidget {
  const _RoleEditorSheet({
    required this.initialRole,
    required this.onSave,
    required this.onPolishRoleIntent,
  });

  final MobileCodeRole? initialRole;
  final ValueChanged<MobileCodeRole> onSave;
  final Future<String> Function(String intent)? onPolishRoleIntent;

  @override
  State<_RoleEditorSheet> createState() => _RoleEditorSheetState();
}

class _RoleEditorSheetState extends State<_RoleEditorSheet> {
  final _intent = TextEditingController();
  final _name = TextEditingController();
  final _summary = TextEditingController();
  final _mission = TextEditingController();
  final _personality = TextEditingController();
  final _responsibilities = TextEditingController();
  final _guardrails = TextEditingController();
  final _successCriteria = TextEditingController();
  final _promptTemplate = TextEditingController();
  bool _polishing = false;
  String _avatarAsset = RoleLibraryService.defaultCustomAvatarAsset;
  int _colorValue = 0xFF7557E8;

  @override
  void initState() {
    super.initState();
    final role = widget.initialRole;
    if (role != null) _applyRole(role);
  }

  @override
  void dispose() {
    _intent.dispose();
    _name.dispose();
    _summary.dispose();
    _mission.dispose();
    _personality.dispose();
    _responsibilities.dispose();
    _guardrails.dispose();
    _successCriteria.dispose();
    _promptTemplate.dispose();
    super.dispose();
  }

  void _applyRole(MobileCodeRole role) {
    _name.text = role.name;
    _summary.text = role.summary;
    _mission.text = role.mission;
    _personality.text = role.personality;
    _responsibilities.text = role.responsibilities.join('\n');
    _guardrails.text = role.guardrails.join('\n');
    _successCriteria.text = role.successCriteria.join('\n');
    _promptTemplate.text = role.promptTemplate;
    _avatarAsset = role.avatarAsset;
    _colorValue = role.colorValue;
  }

  Future<void> _polish() async {
    final rawIntent = _intent.text.trim().isEmpty ? _mission.text.trim() : _intent.text.trim();
    if (rawIntent.isEmpty) {
      _snack('先写一句你想要的角色意图');
      return;
    }

    setState(() => _polishing = true);
    try {
      final output = widget.onPolishRoleIntent == null
          ? ''
          : await widget.onPolishRoleIntent!(rawIntent);
      final polished = output.trim().isEmpty
          ? RoleLibraryService.instance.standardizeLocalIntent(rawIntent)
          : RoleLibraryService.instance.parsePolishedOutput(output, fallbackIntent: rawIntent);
      final role = polished.copyWith(avatarAsset: _avatarAsset, colorValue: _colorValue);
      _applyRole(role);
      _snack(output.trim().isEmpty ? '已用本地模板标准化' : 'AI 已润色为标准角色卡');
    } catch (error) {
      final role = RoleLibraryService.instance.standardizeLocalIntent(rawIntent).copyWith(
            avatarAsset: _avatarAsset,
            colorValue: _colorValue,
          );
      _applyRole(role);
      _snack('AI 润色不可用，已用本地模板标准化');
    } finally {
      if (mounted) setState(() => _polishing = false);
    }
  }

  void _save() {
    if (_name.text.trim().isEmpty || _mission.text.trim().isEmpty) {
      _snack('角色名称和使命不能为空');
      return;
    }
    final previous = widget.initialRole;
    final role = MobileCodeRole(
      id: previous?.id ?? '',
      name: _name.text.trim(),
      summary: _summary.text.trim(),
      mission: _mission.text.trim(),
      personality: _personality.text.trim(),
      responsibilities: _lines(_responsibilities.text),
      guardrails: _lines(_guardrails.text),
      successCriteria: _lines(_successCriteria.text),
      promptTemplate: _promptTemplate.text.trim(),
      avatarAsset: _avatarAsset,
      colorValue: _colorValue,
      builtIn: false,
    );
    widget.onSave(role);
    Navigator.of(context).pop();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 14, 16, bottomInset + 16),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.badge_outlined, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.initialRole == null ? 'Create custom role' : 'Edit custom role',
                      style: const TextStyle(
                        fontFamily: AppTheme.fontBody,
                        color: AppTheme.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'AI 润色角色定义',
                    onPressed: _polishing ? null : _polish,
                    icon: _polishing
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.auto_fix_high_outlined, color: AppTheme.primary),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '先用自然语言说清楚你想要什么角色，再点 AI 润色。MobileCode 会用标准角色模板生成可维护的 role card。',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.35),
              ),
              const SizedBox(height: 12),
              _field(_intent, 'Role intent', '例如：帮我定义一个专门检查 GitHub Pages 发布错误的角色', maxLines: 3),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: _polishing ? null : _polish,
                  icon: _polishing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_fix_high_outlined, size: 17),
                  label: const Text('AI 润色角色卡'),
                ),
              ),
              const SizedBox(height: 10),
              _buildAvatarPicker(),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _field(_name, 'Name', 'GitHub Publisher')),
                  const SizedBox(width: 10),
                  Expanded(child: _field(_summary, 'Summary', 'One short sentence')),
                ],
              ),
              _field(_mission, 'Mission', 'This role owns...', maxLines: 2),
              _field(_personality, 'Personality', 'Calm, exact, mobile-first...', maxLines: 2),
              _field(_responsibilities, 'Responsibilities', 'One per line', maxLines: 4),
              _field(_guardrails, 'Guardrails', 'One per line', maxLines: 3),
              _field(_successCriteria, 'Success criteria', 'One per line', maxLines: 3),
              _field(_promptTemplate, 'Prompt template', 'You are...', maxLines: 5),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      label: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('保存角色'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController controller, String label, String hint, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        minLines: 1,
        maxLines: maxLines,
        style: const TextStyle(color: AppTheme.textPrimary, fontFamily: AppTheme.fontBody),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          alignLabelWithHint: maxLines > 1,
          labelStyle: const TextStyle(color: AppTheme.textSecondary),
          hintStyle: const TextStyle(color: AppTheme.textTertiary),
          filled: true,
          fillColor: AppTheme.surfaceInput,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppTheme.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarPicker() {
    final selectedColor = Color(_colorValue);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.backgroundElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Role avatar',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 54,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _roleAvatarChoices.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final asset = _roleAvatarChoices[index];
                final selected = asset == _avatarAsset;
                return InkWell(
                  onTap: () => setState(() => _avatarAsset = asset),
                  borderRadius: BorderRadius.circular(14),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: 50,
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: selected ? selectedColor.withOpacity(0.16) : AppTheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: selected ? selectedColor : AppTheme.border),
                    ),
                    child: SvgPicture.asset(
                      asset,
                      fit: BoxFit.contain,
                      placeholderBuilder: (_) => Icon(Icons.person_outline, color: selectedColor, size: 18),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final colorValue in _roleColorChoices)
                InkWell(
                  onTap: () => setState(() => _colorValue = colorValue),
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Color(colorValue),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: colorValue == _colorValue ? AppTheme.textPrimary : AppTheme.border,
                        width: colorValue == _colorValue ? 2 : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

List<String> _lines(String value) {
  return value
      .split(RegExp(r'[\n;]'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}
