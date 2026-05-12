import 'package:flutter/material.dart';
import '../themes/app_theme.dart';
import '../widgets/gradient_button_widget.dart';

/// Snippet create/edit screen
/// Form with title, language selector, code editor, tags input
class SnippetEditorScreen extends StatefulWidget {
  final String? initialTitle;
  final String? initialCode;
  final String? initialLanguage;
  final List<String>? initialTags;
  final String? snippetSource;

  const SnippetEditorScreen({
    super.key,
    this.initialTitle,
    this.initialCode,
    this.initialLanguage,
    this.initialTags,
    this.snippetSource,
  });

  @override
  State<SnippetEditorScreen> createState() => _SnippetEditorScreenState();
}

class _SnippetEditorScreenState extends State<SnippetEditorScreen> {
  late TextEditingController _titleController;
  late TextEditingController _codeController;
  late TextEditingController _tagController;
  late TextEditingController _descriptionController;

  String _selectedLanguage = 'dart';
  final List<String> _tags = [];
  String _source = 'manual';
  bool _isSaving = false;

  final List<Map<String, String>> _languages = [
    {'value': 'dart', 'label': 'Dart'},
    {'value': 'python', 'label': 'Python'},
    {'value': 'javascript', 'label': 'JavaScript'},
    {'value': 'typescript', 'label': 'TypeScript'},
    {'value': 'go', 'label': 'Go'},
    {'value': 'rust', 'label': 'Rust'},
    {'value': 'java', 'label': 'Java'},
    {'value': 'kotlin', 'label': 'Kotlin'},
    {'value': 'swift', 'label': 'Swift'},
    {'value': 'cpp', 'label': 'C++'},
    {'value': 'c', 'label': 'C'},
    {'value': 'csharp', 'label': 'C#'},
    {'value': 'ruby', 'label': 'Ruby'},
    {'value': 'php', 'label': 'PHP'},
    {'value': 'html', 'label': 'HTML'},
    {'value': 'css', 'label': 'CSS'},
    {'value': 'sql', 'label': 'SQL'},
    {'value': 'bash', 'label': 'Bash'},
    {'value': 'json', 'label': 'JSON'},
    {'value': 'yaml', 'label': 'YAML'},
    {'value': 'markdown', 'label': 'Markdown'},
    {'value': 'text', 'label': 'Plain Text'},
  ];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _codeController = TextEditingController(text: widget.initialCode);
    _tagController = TextEditingController();
    _descriptionController = TextEditingController();
    _selectedLanguage = widget.initialLanguage ?? 'dart';
    if (widget.initialTags != null) _tags.addAll(widget.initialTags!);
    _source = widget.snippetSource ?? 'manual';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _codeController.dispose();
    _tagController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _addTag(String tag) {
    tag = tag.trim().toLowerCase();
    if (tag.isNotEmpty && !_tags.contains(tag)) {
      setState(() => _tags.add(tag));
    }
    _tagController.clear();
  }

  void _removeTag(String tag) {
    setState(() => _tags.remove(tag));
  }

  Future<void> _saveSnippet() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入标题')),
      );
      return;
    }
    if (_codeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入代码')),
      );
      return;
    }

    setState(() => _isSaving = true);

    // Simulate save
    await Future.delayed(const Duration(milliseconds: 800));

    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('代码片段已保存')),
      );
      Navigator.pop(context);
    }
  }

  void _showSourceSelector() {
    final sources = [
      {'value': 'manual', 'label': '手动输入', 'icon': Icons.edit},
      {'value': 'voice', 'label': '语音捕捉', 'icon': Icons.mic},
      {'value': 'screenshot', 'label': '截图捕捉', 'icon': Icons.camera_alt},
      {'value': 'github', 'label': 'GitHub', 'icon': Icons.code},
      {'value': 'ai', 'label': 'AI生成', 'icon': Icons.auto_awesome},
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '来源',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              ...sources.map((s) => ListTile(
                    leading: Icon(
                      s['icon'] as IconData,
                      color: _source == s['value']
                          ? AppTheme.violetLight
                          : AppTheme.textSecondary,
                    ),
                    title: Text(
                      s['label'] as String,
                      style: TextStyle(
                        color: _source == s['value']
                            ? AppTheme.textPrimary
                            : AppTheme.textSecondary,
                        fontWeight: _source == s['value']
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                    trailing: _source == s['value']
                        ? const Icon(Icons.check, color: AppTheme.violetLight, size: 20)
                        : null,
                    onTap: () {
                      setState(() => _source = s['value'] as String);
                      Navigator.pop(context);
                    },
                  )),
            ],
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
        title: Text(
          widget.initialTitle == null ? '新建片段' : '编辑片段',
          style: const TextStyle(color: AppTheme.textPrimary),
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: AppTheme.textSecondary),
        ),
        actions: [
          if (_isSaving)
            const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(AppTheme.violetLight),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _saveSnippet,
              child: const Text(
                '保存',
                style: TextStyle(
                  color: AppTheme.cyan,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title input
                    TextField(
                      controller: _titleController,
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: const InputDecoration(
                        labelText: '标题',
                        labelStyle: TextStyle(color: AppTheme.textSecondary),
                        hintText: '给代码片段起个名字',
                        hintStyle: TextStyle(color: AppTheme.textTertiary),
                        prefixIcon:
                            Icon(Icons.title, color: AppTheme.textTertiary),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Description input (optional)
                    TextField(
                      controller: _descriptionController,
                      style: const TextStyle(color: AppTheme.textPrimary),
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: '描述 (可选)',
                        labelStyle: TextStyle(color: AppTheme.textSecondary),
                        hintText: '简要描述这段代码的用途',
                        hintStyle: TextStyle(color: AppTheme.textTertiary),
                        prefixIcon: Icon(Icons.description,
                            color: AppTheme.textTertiary),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Language selector
                    Row(
                      children: [
                        const Icon(Icons.code, color: AppTheme.textSecondary, size: 20),
                        const SizedBox(width: 12),
                        const Text(
                          '语言',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceElevated,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppTheme.border),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedLanguage,
                                isExpanded: true,
                                dropdownColor: AppTheme.surfaceElevated,
                                icon: const Icon(Icons.arrow_drop_down,
                                    color: AppTheme.textSecondary),
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 14,
                                ),
                                onChanged: (v) =>
                                    setState(() => _selectedLanguage = v!),
                                items: _languages.map((lang) {
                                  return DropdownMenuItem(
                                    value: lang['value'],
                                    child: Text(lang['label']!),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Source selector
                    InkWell(
                      onTap: _showSourceSelector,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceElevated,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _getSourceIcon(_source),
                              color: AppTheme.textSecondary,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '来源',
                                    style: TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    _getSourceLabel(_source),
                                    style: const TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right,
                                color: AppTheme.textTertiary, size: 20),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Tags input
                    const Text(
                      '标签',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ..._tags.map((tag) => Chip(
                              label: Text(tag),
                              deleteIcon: const Icon(Icons.close, size: 16),
                              onDeleted: () => _removeTag(tag),
                              backgroundColor:
                                  AppTheme.violet.withOpacity(0.15),
                              labelStyle:
                                  const TextStyle(color: AppTheme.violetLight),
                              deleteIconColor: AppTheme.violetLight,
                            )),
                        SizedBox(
                          width: 120,
                          child: TextField(
                            controller: _tagController,
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 13,
                            ),
                            decoration: InputDecoration(
                              hintText: '添加标签',
                              hintStyle: TextStyle(
                                color: AppTheme.textTertiary.withOpacity(0.5),
                                fontSize: 13,
                              ),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    const BorderSide(color: AppTheme.border),
                              ),
                            ),
                            onSubmitted: _addTag,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Code editor
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '代码',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          '${_codeController.text.split('\n').length} 行',
                          style: const TextStyle(
                            color: AppTheme.textTertiary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceDark,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: TextField(
                        controller: _codeController,
                        style: const TextStyle(
                          fontSize: 13,
                          fontFamily: AppTheme.fontCode,
                          color: AppTheme.textPrimary,
                          height: 1.6,
                        ),
                        maxLines: 15,
                        decoration: const InputDecoration(
                          hintText: '在此输入代码...',
                          hintStyle: TextStyle(
                            color: AppTheme.textTertiary,
                            fontFamily: AppTheme.fontCode,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.all(16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Save button
                    GradientButtonWidget(
                      label: '保存片段',
                      icon: Icons.save,
                      onPressed: _saveSnippet,
                      isLoading: _isSaving,
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getSourceIcon(String source) {
    switch (source) {
      case 'voice':
        return Icons.mic;
      case 'screenshot':
        return Icons.camera_alt;
      case 'github':
        return Icons.code;
      case 'ai':
        return Icons.auto_awesome;
      default:
        return Icons.edit;
    }
  }

  String _getSourceLabel(String source) {
    switch (source) {
      case 'voice':
        return '语音捕捉';
      case 'screenshot':
        return '截图捕捉';
      case 'github':
        return 'GitHub';
      case 'ai':
        return 'AI生成';
      default:
        return '手动输入';
    }
  }
}
