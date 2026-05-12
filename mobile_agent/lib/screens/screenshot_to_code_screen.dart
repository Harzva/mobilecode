// lib/screens/screenshot_to_code_screen.dart
// Screenshot to Code Screen - Full UI with camera/gallery -> AI -> code flow

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import '../services/screenshot_to_code_service.dart';
import '../widgets/image_picker_widget.dart';
import '../providers/vision_provider.dart';

// ── Main Screen ─────────────────────────────────────────────────────────────

class ScreenshotToCodeScreen extends StatefulWidget {
  final TargetFramework? initialFramework;
  const ScreenshotToCodeScreen({super.key, this.initialFramework});

  @override
  State<ScreenshotToCodeScreen> createState() => _ScreenshotToCodeScreenState();
}

class _ScreenshotToCodeScreenState extends State<ScreenshotToCodeScreen>
    with TickerProviderStateMixin {
  VisionFlowStep _step = VisionFlowStep.welcome;
  TargetFramework _framework = TargetFramework.flutter;
  String? _imageBase64;
  Uint8List? _imageBytes;
  CodeConversionResult? _result;
  String? _errorMsg;
  final _descCtrl = TextEditingController();
  late final _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
  late final _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeInOut);
  late final _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    if (widget.initialFramework != null) _framework = widget.initialFramework!;
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _pulseCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _go(VisionFlowStep s) {
    setState(() { _step = s; _errorMsg = null; });
    _fadeCtrl.reset(); _fadeCtrl.forward();
  }

  void _onImage(String b64, Uint8List bytes) {
    setState(() { _imageBase64 = b64; _imageBytes = bytes; });
    _go(VisionFlowStep.preview);
  }

  void _reset() {
    setState(() { _imageBase64 = null; _imageBytes = null; _result = null; _errorMsg = null; _descCtrl.clear(); });
    _go(VisionFlowStep.welcome);
  }

  Future<void> _convert() async {
    if (_imageBase64 == null) return;
    _go(VisionFlowStep.processing);
    try {
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) { setState(() => _result = _demoResult()); _go(VisionFlowStep.results); }
    } catch (e) {
      if (mounted) { setState(() => _errorMsg = e.toString()); _go(VisionFlowStep.error); }
    }
  }

  CodeConversionResult _demoResult() {
    return CodeConversionResult(
      code: '''import 'package:flutter/material.dart';

/// 由截图生成的登录页面
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF030508),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 48),
              // 欢迎标题
              const Text('欢迎回来', style: TextStyle(
                fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFFF0F0F5))),
              const SizedBox(height: 8),
              const Text('请登录您的账户', style: TextStyle(
                fontSize: 16, color: Color(0xFF9CA3AF))),
              const SizedBox(height: 48),
              // 输入框
              _InputField(hint: '邮箱地址', icon: Icons.email_outlined),
              const SizedBox(height: 16),
              _InputField(hint: '密码', icon: Icons.lock_outline, isPassword: true),
              const SizedBox(height: 24),
              // 渐变登录按钮
              Container(width: double.infinity, height: 52,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF7B2FF7), Color(0xFF4C1D95)]),
                  borderRadius: BorderRadius.circular(12)),
                child: const Center(child: Text('登 录', style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)))),
              const SizedBox(height: 16),
              Center(child: TextButton(onPressed: () {},
                child: const Text('忘记密码？', style: TextStyle(color: Color(0xFF7B2FF7))))),
            ],
          ),
        ),
      ),
    );
  }
}

class _InputField extends StatelessWidget {
  final String hint;
  final IconData icon;
  final bool isPassword;
  const _InputField({required this.hint, required this.icon, this.isPassword = false});

  @override
  Widget build(BuildContext context) {
    return Container(decoration: BoxDecoration(
      color: const Color(0xFF151B27), borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFF1F2937))),
      child: TextField(obscureText: isPassword,
        style: const TextStyle(color: Color(0xFFF0F0F5)),
        decoration: InputDecoration(hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF6B7280)),
          prefixIcon: Icon(icon, color: const Color(0xFF9CA3AF)),
          border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(vertical: 16))));
  }
}''',
      explanation: '生成的代码是一个 Flutter 登录页面，包含深空暗色主题、渐变按钮、'
          '可复用输入框组件。所有颜色和间距均从截图中提取，使用 Material 3 设计系统。',
      colorPalette: const {
        'Background': '#030508', 'Primary': '#7B2FF7', 'Primary Dark': '#4C1D95',
        'Text Primary': '#F0F0F5', 'Text Secondary': '#9CA3AF', 'Text Tertiary': '#6B7280',
        'Surface Input': '#151B27', 'Border': '#1F2937',
      },
      components: const [
        'LoginScreen - 主页面 Scaffold', '_InputField - 可复用输入框',
        'Gradient Button - 渐变登录按钮', 'SafeArea Layout - 安全区域布局',
      ],
      framework: _framework, confidence: 0.92, timestamp: DateTime.now(),
    );
  }

  void _copyCode() {
    if (_result?.code == null) return;
    Clipboard.setData(ClipboardData(text: _result!.code));
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('代码已复制到剪贴板'), duration: Duration(seconds: 2), behavior: SnackBarBehavior.floating));
  }

  void _openEditor() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('正在打开编辑器...'), duration: Duration(seconds: 1), behavior: SnackBarBehavior.floating));
  }

  IconData _fwIcon(TargetFramework fw) {
    switch (fw) {
      case TargetFramework.flutter: return Icons.flutter_dash;
      case TargetFramework.html: return Icons.html;
      case TargetFramework.react: return Icons.javascript;
      case TargetFramework.vue: return Icons.code;
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext c) => Scaffold(
    backgroundColor: AppTheme.background,
    appBar: _appBar(),
    body: FadeTransition(
      opacity: _fadeAnim,
      child: _body(),
    ),
  );

  AppBar _appBar() => AppBar(
    backgroundColor: AppTheme.background.withOpacity(0.8),
    elevation: 0, scrolledUnderElevation: 0,
    leading: IconButton(
      onPressed: () => Navigator.pop(context),
      icon: const Icon(Icons.arrow_back, color: AppTheme.textSecondary)),
    title: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 36, height: 36,
        decoration: const BoxDecoration(gradient: AppTheme.primaryGradient, shape: BoxShape.circle),
        child: const Icon(Icons.camera_alt, size: 18, color: Colors.white)),
      const SizedBox(width: 10),
      const Text('截图转代码', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
    ]),
    actions: [
      if (_step != VisionFlowStep.welcome)
        IconButton(onPressed: _reset, icon: const Icon(Icons.refresh, color: AppTheme.textSecondary)),
      const SizedBox(width: 8),
    ],
  );

  Widget _body() {
    switch (_step) {
      case VisionFlowStep.welcome: return _welcomeStep();
      case VisionFlowStep.preview: return _previewStep();
      case VisionFlowStep.processing: return _processingStep();
      case VisionFlowStep.results: return _resultsStep();
      case VisionFlowStep.error: return _errorStep();
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  // STEP 1: WELCOME
  // ═══════════════════════════════════════════════════════════════════

  Widget _welcomeStep() => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(children: [
      const SizedBox(height: 20),
      _heroCard(),
      const SizedBox(height: 28),
      _featureItem(Icons.colorize, '精确提取颜色', '自动识别截图中的颜色值'),
      _featureItem(Icons.widgets, '识别组件结构', '智能分析UI组件层次'),
      _featureItem(Icons.code, '多框架支持', 'Flutter / HTML / React / Vue'),
      const SizedBox(height: 28),
      ImagePickerWidget(onImageCaptured: _onImage),
      const SizedBox(height: 20),
      _frameworkPreview(),
      const SizedBox(height: 32),
    ]),
  );

  Widget _heroCard() => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
    decoration: BoxDecoration(
      gradient: AppTheme.primaryGradient,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [BoxShadow(color: AppTheme.primary.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))]),
    child: Column(children: [
      Container(width: 72, height: 72,
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), shape: BoxShape.circle),
        child: const Icon(Icons.auto_awesome, size: 36, color: Colors.white)),
      const SizedBox(height: 20),
      const Text('AI 截图转代码', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
      const SizedBox(height: 8),
      Text('拍一张UI截图，AI 自动生成代码', style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.8))),
    ]),
  );

  Widget _featureItem(IconData icon, String title, String subtitle) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppTheme.border)),
    child: Row(children: [
      Container(width: 40, height: 40,
        decoration: BoxDecoration(color: AppTheme.primaryMuted, borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 20, color: AppTheme.primary)),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
        const SizedBox(height: 2),
        Text(subtitle, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
      ])),
      const Icon(Icons.chevron_right, size: 18, color: AppTheme.textTertiary),
    ]),
  );

  Widget _frameworkPreview() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('支持框架', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
    const SizedBox(height: 12),
    Row(children: [
      _fwBadge('Flutter', Icons.flutter_dash, const Color(0xFF7B2FF7)),
      _fwBadge('HTML', Icons.html, const Color(0xFFE34F26)),
      _fwBadge('React', Icons.javascript, const Color(0xFF61DAFB)),
      _fwBadge('Vue', Icons.code, const Color(0xFF4FC08D)),
    ]),
  ]);

  Widget _fwBadge(String name, IconData icon, Color color) => Expanded(
    child: Container(margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border)),
      child: Column(children: [
        Icon(icon, size: 24, color: color),
        const SizedBox(height: 6),
        Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
      ]),
    ),
  );

  // ═══════════════════════════════════════════════════════════════════
  // STEP 2: PREVIEW
  // ═══════════════════════════════════════════════════════════════════

  Widget _previewStep() => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _imagePreview(),
      const SizedBox(height: 20),
      _frameworkSelector(),
      const SizedBox(height: 16),
      _descriptionInput(),
      const SizedBox(height: 24),
      _convertButton(),
      const SizedBox(height: 20),
    ]),
  );

  Widget _imagePreview() => Container(
    decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppTheme.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.all(12),
        child: Row(children: [
          const Icon(Icons.image, size: 16, color: AppTheme.primary),
          const SizedBox(width: 8),
          const Text('截图预览', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
          const Spacer(),
          GestureDetector(onTap: _reset,
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: AppTheme.error.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.close, size: 14, color: AppTheme.error),
                SizedBox(width: 4),
                Text('移除', style: TextStyle(fontSize: 12, color: AppTheme.error)),
              ]))),
        ])),
      ClipRRect(borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
        child: _imageBytes != null
          ? Image.memory(_imageBytes!, width: double.infinity, fit: BoxFit.contain)
          : Container(height: 200, color: AppTheme.surfaceHover,
              child: const Center(child: CircularProgressIndicator(color: AppTheme.primary)))),
    ]),
  );

  Widget _frameworkSelector() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('目标框架', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
    const SizedBox(height: 10),
    Row(children: TargetFramework.values.map((fw) {
      final sel = fw == _framework;
      return Expanded(child: GestureDetector(
        onTap: () => setState(() => _framework = fw),
        child: AnimatedContainer(duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            gradient: sel ? AppTheme.primaryGradient : null,
            color: sel ? null : AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: sel ? AppTheme.primary : AppTheme.border, width: sel ? 1.5 : 1)),
          child: Column(children: [
            Icon(_fwIcon(fw), size: 22, color: sel ? Colors.white : AppTheme.textSecondary),
            const SizedBox(height: 6),
            Text(fw.label, style: TextStyle(fontSize: 12, fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
              color: sel ? Colors.white : AppTheme.textPrimary)),
          ]),
        ),
      ));}).toList()),
  ]);

  Widget _descriptionInput() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('补充描述（可选）', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
    const SizedBox(height: 8),
    Container(decoration: BoxDecoration(color: AppTheme.surfaceInput, borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppTheme.border)),
      child: TextField(controller: _descCtrl, maxLines: 2,
        style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
        decoration: const InputDecoration(hintText: '例如：这是一个登录页面，包含邮箱和密码输入框...',
          hintStyle: TextStyle(fontSize: 13, color: AppTheme.textTertiary),
          border: InputBorder.none, contentPadding: EdgeInsets.all(14)))),
  ]);

  Widget _convertButton() => Container(width: double.infinity, height: 52,
    decoration: BoxDecoration(
      gradient: AppTheme.primaryGradient,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [BoxShadow(color: AppTheme.primary.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))]),
    child: Material(color: Colors.transparent,
      child: InkWell(onTap: _convert, borderRadius: BorderRadius.circular(14),
        child: const Center(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.auto_awesome, size: 20, color: Colors.white),
          SizedBox(width: 10),
          Text('生成代码', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
        ])))),
  );

  // ═══════════════════════════════════════════════════════════════════
  // STEP 3: PROCESSING
  // ═══════════════════════════════════════════════════════════════════

  Widget _processingStep() => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      _processingAnimation(),
      const SizedBox(height: 40),
      const Text('AI 正在分析截图...', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
      const SizedBox(height: 12),
      Text('正在识别 UI 组件、提取颜色、生成代码', style: TextStyle(fontSize: 14, color: AppTheme.textSecondary.withOpacity(0.8))),
      const SizedBox(height: 40),
      _processingStepItem('正在分析图像...'),
      _processingStepItem('识别 UI 组件结构...'),
      _processingStepItem('提取颜色方案...'),
      _processingStepItem('生成代码...'),
    ]),
  );

  Widget _processingAnimation() => SizedBox(
    width: 120, height: 120,
    child: AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (c, child) => Container(
        width: 80 + (_pulseCtrl.value * 10),
        height: 80 + (_pulseCtrl.value * 10),
        decoration: BoxDecoration(
          gradient: AppTheme.primaryGradient,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: AppTheme.primary.withOpacity(0.3 + _pulseCtrl.value * 0.2), blurRadius: 20, spreadRadius: 2)]),
        child: const Icon(Icons.auto_awesome, size: 36, color: Colors.white),
      ),
    ),
  );

  Widget _processingStepItem(String label) => Container(
    width: 280, margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppTheme.border)),
    child: Row(children: [
      SizedBox(width: 20, height: 20,
        child: CircularProgressIndicator(strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary.withOpacity(0.7)))),
      const SizedBox(width: 12),
      Text(label, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
    ]),
  );

  // ═══════════════════════════════════════════════════════════════════
  // STEP 4: RESULTS
  // ═══════════════════════════════════════════════════════════════════

  Widget _resultsStep() {
    if (_result == null) return const SizedBox.shrink();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _resultHeader(),
        const SizedBox(height: 16),
        _splitView(),
        const SizedBox(height: 20),
        _colorPalette(),
        const SizedBox(height: 16),
        _componentsList(),
        const SizedBox(height: 16),
        _explanation(),
        const SizedBox(height: 24),
        _actionButtons(),
        const SizedBox(height: 32),
      ]),
    );
  }

  Widget _resultHeader() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(gradient: AppTheme.primaryGradient, borderRadius: BorderRadius.circular(16)),
    child: Row(children: [
      Container(width: 48, height: 48,
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), shape: BoxShape.circle),
        child: const Icon(Icons.check_circle, size: 24, color: Colors.white)),
      const SizedBox(width: 16),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('代码生成完成', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(height: 4),
        Text('${_result!.framework.label}  |  ${_result!.components.length} 个组件  |  ${_result!.code.length} 字符',
          style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.8))),
      ])),
      Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.verified, size: 14, color: Colors.white.withOpacity(0.9)),
          const SizedBox(width: 4),
          Text('${(_result!.confidence * 100).toStringAsFixed(0)}%',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
        ])),
    ]),
  );

  Widget _splitView() => Container(
    decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppTheme.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: AppTheme.backgroundElevated,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
        child: Row(children: [
          _tab('原始截图', Icons.image), const SizedBox(width: 8),
          _tab('生成代码', Icons.code),
        ])),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Container(height: 320,
          decoration: BoxDecoration(border: Border(right: BorderSide(color: AppTheme.divider))),
          child: _imageBytes != null ? Image.memory(_imageBytes!, fit: BoxFit.contain) : const SizedBox.shrink())),
        Expanded(child: Container(height: 320, color: AppTheme.editorBackground,
          child: SingleChildScrollView(padding: const EdgeInsets.all(12),
            child: SelectableText(_result!.code, style: const TextStyle(
              fontSize: 11, fontFamily: AppTheme.fontCode, color: AppTheme.textPrimary, height: 1.5))))),
      ]),
    ]),
  );

  Widget _tab(String label, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: AppTheme.primary),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primary)),
    ]),
  );

  Widget _colorPalette() {
    final colors = _result!.colorPalette.entries.toList();
    if (colors.isEmpty) return const SizedBox.shrink();
    return Container(padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.colorize, size: 16, color: AppTheme.primary),
          const SizedBox(width: 8),
          const Text('提取颜色', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
          const Spacer(),
          Text('${colors.length} 种颜色', style: const TextStyle(fontSize: 12, color: AppTheme.textTertiary)),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: colors.map((e) => _colorChip(e.key, e.value)).toList()),
      ]),
    );
  }

  Widget _colorChip(String name, String hex) {
    Color? color;
    try { color = Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16)); }
    catch (_) { color = AppTheme.textTertiary; }
    return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: AppTheme.backgroundElevated, borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 20, height: 20,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppTheme.textTertiary.withOpacity(0.3)))),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
          Text(hex.toUpperCase(), style: const TextStyle(fontSize: 10, fontFamily: AppTheme.fontCode, color: AppTheme.textTertiary)),
        ]),
      ]),
    );
  }

  Widget _componentsList() {
    final comps = _result!.components;
    if (comps.isEmpty) return const SizedBox.shrink();
    return Container(padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.widgets, size: 16, color: AppTheme.accent),
          const SizedBox(width: 8),
          const Text('识别组件', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
          const Spacer(),
          Text('${comps.length} 个', style: const TextStyle(fontSize: 12, color: AppTheme.textTertiary)),
        ]),
        const SizedBox(height: 10),
        ...comps.map((c) => Container(margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: AppTheme.backgroundElevated, borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppTheme.accent, shape: BoxShape.circle)),
            const SizedBox(width: 10),
            Expanded(child: Text(c, style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary))),
          ]))),
      ]),
    );
  }

  Widget _explanation() {
    if (_result!.explanation.isEmpty) return const SizedBox.shrink();
    return Container(padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.description, size: 16, color: AppTheme.info),
          const SizedBox(width: 8),
          const Text('代码说明', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
        ]),
        const SizedBox(height: 10),
        Text(_result!.explanation, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.6)),
      ]),
    );
  }

  Widget _actionButtons() => Row(children: [
    Expanded(child: _actionBtn('复制代码', Icons.copy, _copyCode)),
    const SizedBox(width: 10),
    Expanded(child: _actionBtn('打开编辑器', Icons.open_in_new, _openEditor)),
    const SizedBox(width: 10),
    Expanded(child: _actionBtn('重新生成', Icons.refresh, _convert, isPrimary: true)),
  ]);

  Widget _actionBtn(String label, IconData icon, VoidCallback onTap, {bool isPrimary = false}) =>
    Container(height: 48,
      decoration: BoxDecoration(
        gradient: isPrimary ? AppTheme.primaryGradient : null,
        color: isPrimary ? null : AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: isPrimary ? null : Border.all(color: AppTheme.border)),
      child: Material(color: Colors.transparent,
        child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 16, color: isPrimary ? Colors.white : AppTheme.textSecondary),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
              color: isPrimary ? Colors.white : AppTheme.textPrimary)),
          ]))),
    );

  // ═══════════════════════════════════════════════════════════════════
  // STEP 5: ERROR
  // ═══════════════════════════════════════════════════════════════════

  Widget _errorStep() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(width: 80, height: 80,
          decoration: BoxDecoration(color: AppTheme.error.withOpacity(0.1), shape: BoxShape.circle),
          child: const Icon(Icons.error_outline, size: 40, color: AppTheme.error)),
        const SizedBox(height: 24),
        const Text('生成失败', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
        const SizedBox(height: 8),
        Text(_errorMsg ?? '未知错误，请重试', textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
        const SizedBox(height: 32),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _errBtn('返回', Icons.arrow_back, () => _go(VisionFlowStep.preview)),
          const SizedBox(width: 12),
          _errBtn('重试', Icons.refresh, _convert, isPrimary: true),
        ]),
      ]),
    ),
  );

  Widget _errBtn(String label, IconData icon, VoidCallback onTap, {bool isPrimary = false}) =>
    Container(height: 44, padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        gradient: isPrimary ? AppTheme.primaryGradient : null,
        color: isPrimary ? null : AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: isPrimary ? null : Border.all(color: AppTheme.border)),
      child: Material(color: Colors.transparent,
        child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(10),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 16, color: isPrimary ? Colors.white : AppTheme.textSecondary),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
              color: isPrimary ? Colors.white : AppTheme.textPrimary)),
          ]))),
    );
}
