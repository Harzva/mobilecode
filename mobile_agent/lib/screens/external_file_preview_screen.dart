import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/external_file_preview_service.dart';
import '../themes/app_theme.dart';
import 'editor_screen.dart';

enum _PreviewMode { rendered, source }

class ExternalFilePreviewScreen extends StatefulWidget {
  const ExternalFilePreviewScreen({
    super.key,
    required this.file,
  });

  final ExternalPreviewFile file;

  @override
  State<ExternalFilePreviewScreen> createState() => _ExternalFilePreviewScreenState();
}

class _ExternalFilePreviewScreenState extends State<ExternalFilePreviewScreen> {
  _PreviewMode _mode = _PreviewMode.rendered;
  late final Future<String> _textFuture;
  WebViewController? _htmlController;
  bool _htmlLoading = false;
  String? _htmlError;

  @override
  void initState() {
    super.initState();
    _textFuture = widget.file.readText();
    if (widget.file.kind == ExternalPreviewKind.html) {
      _initHtmlController();
    }
    if (widget.file.kind == ExternalPreviewKind.text ||
        widget.file.kind == ExternalPreviewKind.unsupported) {
      _mode = _PreviewMode.source;
    }
  }

  Future<void> _initHtmlController() async {
    setState(() {
      _htmlLoading = true;
      _htmlError = null;
    });
    try {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.white)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (_) {
              if (mounted) setState(() => _htmlLoading = false);
            },
            onWebResourceError: (error) {
              if (!mounted) return;
              setState(() {
                _htmlLoading = false;
                _htmlError = error.description;
              });
            },
          ),
        );
      await controller.loadFile(widget.file.path);
      if (!mounted) return;
      setState(() => _htmlController = controller);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _htmlLoading = false;
        _htmlError = error.toString();
      });
    }
  }

  void _openInEditor() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EditorScreen(
          initialFilePath: widget.file.path,
          fileName: widget.file.displayName,
          language: _editorLanguage(widget.file.kind),
          readOnly: true,
        ),
      ),
    );
  }

  String _editorLanguage(ExternalPreviewKind kind) {
    switch (kind) {
      case ExternalPreviewKind.html:
        return 'html';
      case ExternalPreviewKind.markdown:
        return 'markdown';
      case ExternalPreviewKind.text:
      case ExternalPreviewKind.unsupported:
        return 'text';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.auroraBackground,
      appBar: AppBar(
        title: const Text('文件预览'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: '返回',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          IconButton(
            tooltip: '用代码编辑器查看',
            onPressed: widget.file.isTextReadable ? _openInEditor : null,
            icon: const Icon(Icons.code_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _Header(file: widget.file),
            if (_supportsRenderedAndSource(widget.file.kind)) _modeSwitch(),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  bool _supportsRenderedAndSource(ExternalPreviewKind kind) {
    return kind == ExternalPreviewKind.html || kind == ExternalPreviewKind.markdown;
  }

  Widget _modeSwitch() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: SegmentedButton<_PreviewMode>(
        segments: const [
          ButtonSegment(
            value: _PreviewMode.rendered,
            icon: Icon(Icons.visibility_rounded, size: 16),
            label: Text('预览'),
          ),
          ButtonSegment(
            value: _PreviewMode.source,
            icon: Icon(Icons.code_rounded, size: 16),
            label: Text('源码'),
          ),
        ],
        selected: {_mode},
        onSelectionChanged: (selected) => setState(() => _mode = selected.first),
        showSelectedIcon: false,
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          side: WidgetStateProperty.all(const BorderSide(color: AppTheme.auroraBorder)),
        ),
      ),
    );
  }

  Widget _body() {
    if (widget.file.kind == ExternalPreviewKind.unsupported) {
      return _unsupported();
    }
    if (_mode == _PreviewMode.source) {
      return _sourceView();
    }
    switch (widget.file.kind) {
      case ExternalPreviewKind.html:
        return _htmlPreview();
      case ExternalPreviewKind.markdown:
        return _markdownPreview();
      case ExternalPreviewKind.text:
        return _sourceView();
      case ExternalPreviewKind.unsupported:
        return _unsupported();
    }
  }

  Widget _htmlPreview() {
    if (_htmlError != null) {
      return _MessagePanel(
        icon: Icons.error_outline_rounded,
        title: 'HTML 预览失败',
        message: _htmlError!,
        actionLabel: '查看源码',
        onAction: () => setState(() => _mode = _PreviewMode.source),
      );
    }
    final controller = _htmlController;
    if (controller == null || _htmlLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.auroraBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: WebViewWidget(controller: controller),
    );
  }

  Widget _markdownPreview() {
    return FutureBuilder<String>(
      future: _textFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _MessagePanel(
            icon: Icons.error_outline_rounded,
            title: 'Markdown 读取失败',
            message: snapshot.error.toString(),
          );
        }
        return Markdown(
          data: snapshot.data ?? '',
          selectable: true,
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
          styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
            h1: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppTheme.auroraText),
            h2: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.auroraText),
            p: const TextStyle(fontSize: 15, height: 1.62, color: AppTheme.auroraText),
            code: const TextStyle(
              fontFamily: AppTheme.fontCode,
              fontSize: 13,
              color: AppTheme.auroraBlue,
              backgroundColor: AppTheme.auroraSurfaceSoft,
            ),
            codeblockDecoration: BoxDecoration(
              color: AppTheme.auroraSurfaceSoft,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.auroraBorder),
            ),
          ),
        );
      },
    );
  }

  Widget _sourceView() {
    return FutureBuilder<String>(
      future: _textFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _MessagePanel(
            icon: Icons.error_outline_rounded,
            title: '文件读取失败',
            message: snapshot.error.toString(),
          );
        }
        final text = snapshot.data ?? '';
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          decoration: BoxDecoration(
            color: const Color(0xFF0D1117),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.auroraBorder),
          ),
          child: Column(
            children: [
              Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0xFF1F2937))),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.article_outlined, size: 16, color: Color(0xFF9CA3AF)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.file.sizeBytes > 1024 * 1024
                            ? '显示前 1 MB 内容'
                            : '源码 / 原文',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF9CA3AF),
                          fontSize: 12,
                          fontFamily: AppTheme.fontCode,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(14),
                  child: SelectableText(
                    text,
                    style: const TextStyle(
                      color: Color(0xFFE5E7EB),
                      fontSize: 13,
                      height: 1.55,
                      fontFamily: AppTheme.fontCode,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _unsupported() {
    return _MessagePanel(
      icon: Icons.block_rounded,
      title: '暂不支持预览此文件',
      message: 'MobileCode 已接收文件，但它看起来不是 HTML、Markdown 或可读文本。'
          ' 为安全起见不会按文本强行打开。',
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.file});

  final ExternalPreviewFile file;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.auroraSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.auroraBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.auroraSurfaceSoft,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.auroraBorder),
            ),
            child: Icon(_icon(file.kind), color: AppTheme.auroraBlue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.auroraText,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _Badge(label: file.kindLabel),
                    _Badge(label: file.shortSize),
                    if (file.mimeType.isNotEmpty) _Badge(label: file.mimeType),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _icon(ExternalPreviewKind kind) {
    switch (kind) {
      case ExternalPreviewKind.html:
        return Icons.html_rounded;
      case ExternalPreviewKind.markdown:
        return Icons.notes_rounded;
      case ExternalPreviewKind.text:
        return Icons.description_outlined;
      case ExternalPreviewKind.unsupported:
        return Icons.insert_drive_file_outlined;
    }
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.auroraSurfaceSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.auroraBorder),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppTheme.auroraTextMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MessagePanel extends StatelessWidget {
  const _MessagePanel({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 420),
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: AppTheme.auroraSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.auroraBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: AppTheme.auroraTextFaint),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.auroraText,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.auroraTextMuted,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
