import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../themes/app_theme.dart';

/// Reusable code editor widget
/// Wraps a TextField with code editor styling
/// Configurable: language, theme, font size, line numbers
/// Toolbar: undo, redo, format, copy, paste
/// Error/warning indicators
class CodeEditorWidget extends StatefulWidget {
  final String? initialValue;
  final String language;
  final double fontSize;
  final bool showLineNumbers;
  final bool showToolbar;
  final Function(String)? onChanged;
  final Function(int, int)? onCursorChanged;

  const CodeEditorWidget({
    super.key,
    this.initialValue,
    this.language = 'text',
    this.fontSize = 14.0,
    this.showLineNumbers = true,
    this.showToolbar = true,
    this.onChanged,
    this.onCursorChanged,
  });

  @override
  State<CodeEditorWidget> createState() => CodeEditorWidgetState();
}

class CodeEditorWidgetState extends State<CodeEditorWidget> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  final ScrollController _scrollController = ScrollController();
  int _cursorLine = 1;
  int _cursorColumn = 1;
  int _totalLines = 1;

  // Syntax patterns for basic highlighting
  final Map<String, List<({Pattern pattern, TextStyle style})>>
      _syntaxPatterns = {};

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _focusNode = FocusNode();
    _controller.addListener(_onTextChanged);
    _updateStats();
    _initSyntaxPatterns();
  }

  void _initSyntaxPatterns() {
    _syntaxPatterns['dart'] = [
      (
        pattern: RegExp(
            r'\b(import|export|library|part|void|var|final|const|class|extends|implements|with|static|abstract|async|await|return|if|else|for|while|do|switch|case|break|continue|default|try|catch|finally|throw|new|this|super|true|false|null)\b'),
        style: const TextStyle(color: AppTheme.syntaxKeyword),
      ),
      (
        pattern: RegExp(r'".*?"|'.".*?'".'r'),
        style: const TextStyle(color: AppTheme.syntaxString),
      ),
      (
        pattern: RegExp(r'//.*?$|/\*.*?\*/', multiLine: true),
        style: const TextStyle(color: AppTheme.syntaxComment),
      ),
      (
        pattern: RegExp(r'\b\d+\.?\d*\b'),
        style: const TextStyle(color: AppTheme.syntaxNumber),
      ),
    ];

    _syntaxPatterns['python'] = [
      (
        pattern: RegExp(
            r'\b(def|class|return|if|elif|else|for|while|try|except|finally|with|import|from|as|pass|break|continue|lambda|yield|async|await|True|False|None|and|or|not|in|is)\b'),
        style: const TextStyle(color: AppTheme.syntaxKeyword),
      ),
      (
        pattern: RegExp(r'".*?"|'.".*?'".'r'),
        style: const TextStyle(color: AppTheme.syntaxString),
      ),
      (
        pattern: RegExp(r'#.*?$|""".*?"""|\'\'\'.*?\'\'\'', multiLine: true),
        style: const TextStyle(color: AppTheme.syntaxComment),
      ),
    ];

    _syntaxPatterns['javascript'] = [
      (
        pattern: RegExp(
            r'\b(const|let|var|function|return|if|else|for|while|do|switch|case|break|continue|default|try|catch|finally|throw|new|this|class|extends|import|export|from|async|await|true|false|null|undefined)\b'),
        style: const TextStyle(color: AppTheme.syntaxKeyword),
      ),
      (
        pattern: RegExp(r'".*?"|'.".*?'".'r'),
        style: const TextStyle(color: AppTheme.syntaxString),
      ),
      (
        pattern: RegExp(r'//.*?$|/\*.*?\*/', multiLine: true),
        style: const TextStyle(color: AppTheme.syntaxComment),
      ),
    ];
  }

  void _onTextChanged() {
    _updateStats();
    widget.onChanged?.call(_controller.text);
  }

  void _updateStats() {
    final text = _controller.text;
    final lines = text.isEmpty ? 1 : '\n'.allMatches(text).length + 1;
    if (mounted) {
      setState(() {
        _totalLines = lines;
      });
    }
  }

  void _updateCursorPosition() {
    final text = _controller.text;
    final selection = _controller.selection;
    if (selection.isValid && selection.baseOffset >= 0) {
      final upToCursor = text.substring(0, selection.baseOffset);
      final line =
          upToCursor.isEmpty ? 1 : '\n'.allMatches(upToCursor).length + 1;
      final lastNewline = upToCursor.lastIndexOf('\n');
      final col = lastNewline == -1
          ? selection.baseOffset + 1
          : selection.baseOffset - lastNewline;
      setState(() {
        _cursorLine = line;
        _cursorColumn = col;
      });
      widget.onCursorChanged?.call(line, col);
    }
  }

  // ── Public Methods ──

  String get text => _controller.text;

  set text(String value) {
    _controller.text = value;
  }

  TextSelection get selection => _controller.selection;

  void undo() {
    // Would be implemented with edit history
    HapticFeedback.lightImpact();
  }

  void redo() {
    HapticFeedback.lightImpact();
  }

  void format() {
    // Basic formatting - trim trailing whitespace
    final lines = _controller.text.split('\n');
    final formatted =
        lines.map((l) => l.trimRight()).join('\n').trimRight();
    _controller.text = formatted;
    HapticFeedback.mediumImpact();
  }

  void selectAll() {
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  void copy() {
    final selected = _controller.selection;
    if (selected.start != selected.end) {
      final text = _controller.text.substring(selected.start, selected.end);
      Clipboard.setData(ClipboardData(text: text));
      HapticFeedback.lightImpact();
    }
  }

  Future<void> paste() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null) {
      final selection = _controller.selection;
      final text = _controller.text;
      final newText = text.replaceRange(
        selection.start,
        selection.end,
        data!.text!,
      );
      _controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: selection.start + data.text!.length,
        ),
      );
    }
  }

  void insertText(String text) {
    final selection = _controller.selection;
    final currentText = _controller.text;
    final newText = currentText.replaceRange(
      selection.start,
      selection.end,
      text,
    );
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: selection.start + text.length,
      ),
    );
  }

  void clear() {
    _controller.clear();
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.showToolbar) _buildToolbar(),
        Expanded(
          child: Container(
            color: AppTheme.deepSpace,
            child: Row(
              children: [
                if (widget.showLineNumbers) _buildLineNumbers(),
                if (widget.showLineNumbers)
                  Container(
                    width: 1,
                    color: AppTheme.divider.withOpacity(0.5),
                  ),
                Expanded(child: _buildTextField()),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    return Container(
      height: 40,
      decoration: const BoxDecoration(
        color: AppTheme.surfaceDark,
        border: Border(bottom: BorderSide(color: AppTheme.divider)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          _ToolbarIconButton(
            icon: Icons.undo,
            tooltip: '撤销',
            onPressed: undo,
          ),
          _ToolbarIconButton(
            icon: Icons.redo,
            tooltip: '重做',
            onPressed: redo,
          ),
          _buildDivider(),
          _ToolbarIconButton(
            icon: Icons.format_indent_increase,
            tooltip: '格式化',
            onPressed: format,
          ),
          _ToolbarIconButton(
            icon: Icons.content_copy,
            tooltip: '复制',
            onPressed: copy,
          ),
          _ToolbarIconButton(
            icon: Icons.content_paste,
            tooltip: '粘贴',
            onPressed: paste,
          ),
          _ToolbarIconButton(
            icon: Icons.select_all,
            tooltip: '全选',
            onPressed: selectAll,
          ),
          _buildDivider(),
          _ToolbarIconButton(
            icon: Icons.search,
            tooltip: '查找',
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildLineNumbers() {
    return Container(
      width: 48,
      color: AppTheme.deepSpace.withOpacity(0.8),
      child: ListView.builder(
        controller: _scrollController,
        itemCount: _totalLines,
        itemBuilder: (context, index) {
          final lineNum = index + 1;
          final isCurrentLine = lineNum == _cursorLine;
          return Container(
            height: widget.fontSize * 1.6,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 12),
            decoration: isCurrentLine
                ? BoxDecoration(
                    color: AppTheme.violet.withOpacity(0.1),
                    border: const Border(
                      right: BorderSide(color: AppTheme.violet, width: 2),
                    ),
                  )
                : null,
            child: Text(
              '$lineNum',
              style: TextStyle(
                fontSize: widget.fontSize - 2,
                color: isCurrentLine
                    ? AppTheme.textSecondary
                    : AppTheme.textTertiary.withOpacity(0.5),
                fontFamily: AppTheme.fontCode,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTextField() {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      scrollController: _scrollController,
      maxLines: null,
      expands: true,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      style: TextStyle(
        fontSize: widget.fontSize,
        fontFamily: AppTheme.fontCode,
        color: AppTheme.textPrimary,
        height: 1.6,
      ),
      cursorColor: AppTheme.cyan,
      cursorWidth: 2,
      cursorRadius: const Radius.circular(1),
      decoration: const InputDecoration(
        border: InputBorder.none,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        isDense: true,
      ),
      onChanged: (_) => _updateCursorPosition(),
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: AppTheme.divider,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

// ── Toolbar Icon Button ──
class _ToolbarIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _ToolbarIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 18,
              color: AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Error/Warning indicator widget for code editor
class CodeIndicatorWidget extends StatelessWidget {
  final int errorCount;
  final int warningCount;
  final VoidCallback? onTap;

  const CodeIndicatorWidget({
    super.key,
    this.errorCount = 0,
    this.warningCount = 0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (errorCount == 0 && warningCount == 0) return const SizedBox.shrink();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.surfaceDark,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (errorCount > 0) ...[
              const Icon(Icons.error, size: 14, color: AppTheme.error),
              const SizedBox(width: 4),
              Text(
                '$errorCount',
                style: const TextStyle(fontSize: 12, color: AppTheme.error),
              ),
              if (warningCount > 0) const SizedBox(width: 8),
            ],
            if (warningCount > 0) ...[
              const Icon(Icons.warning, size: 14, color: AppTheme.warning),
              const SizedBox(width: 4),
              Text(
                '$warningCount',
                style: const TextStyle(fontSize: 12, color: AppTheme.warning),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
