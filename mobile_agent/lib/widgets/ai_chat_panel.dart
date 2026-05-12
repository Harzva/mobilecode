import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../themes/app_theme.dart';

/// Slide-in AI Chat Panel widget
/// Draggable from right edge with header, messages, input, quick actions
class AiChatPanel extends StatefulWidget {
  final VoidCallback onClose;
  final String? currentCode;
  final String? fileName;
  final String? language;

  const AiChatPanel({
    super.key,
    required this.onClose,
    this.currentCode,
    this.fileName,
    this.language,
  });

  @override
  State<AiChatPanel> createState() => _AiChatPanelState();
}

class _AiChatPanelState extends State<AiChatPanel> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  bool _isTyping = false;

  final List<String> _quickActions = [
    '解释代码',
    '修复错误',
    '优化代码',
    '添加注释',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.currentCode != null && widget.currentCode!.isNotEmpty) {
      _messages.add({
        'id': 'context',
        'role': 'system',
        'content': '当前正在编辑: ${widget.fileName ?? "untitled"}${widget.language != null ? " (${widget.language})" : ""}',
        'timestamp': DateTime.now(),
      });
    }
    _messages.add({
      'id': 'welcome',
      'role': 'assistant',
      'content': '你好！我可以帮你分析代码、修复错误、优化性能，或者回答任何编程问题。',
      'timestamp': DateTime.now(),
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage(String content) {
    if (content.trim().isEmpty) return;

    setState(() {
      _messages.add({
        'id': 'msg_${DateTime.now().millisecondsSinceEpoch}',
        'role': 'user',
        'content': content,
        'timestamp': DateTime.now(),
      });
      _isTyping = true;
    });
    _messageController.clear();
    _scrollToBottom();

    // Simulate response
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) {
        String response;
        if (content.contains('解释')) {
          response = '这段代码的主要功能是初始化一个状态管理类。它使用了单例模式确保全局只有一个实例，并通过`ChangeNotifier`来通知UI更新。\n\n关键点:\n1. 使用`static final`实现单例\n2. 通过`factory`构造函数控制实例创建\n3. 使用`notifyListeners()`触发UI重建';
        } else if (content.contains('修复')) {
          response = '我发现了一个潜在的空指针问题。建议添加空值检查:\n\n```dart\n// 修复前\nString name = user.name;\n\n// 修复后\nString name = user?.name ?? "Anonymous";\n```\n\n这样即使`user`为null也不会崩溃了。';
        } else {
          response = '收到！让我来分析一下这段代码。\n\n整体来看代码结构清晰，建议可以考虑以下几点:\n1. 添加更多的错误处理\n2. 使用更具体的类型而不是dynamic\n3. 为公共方法添加文档注释\n\n有什么具体想让我帮忙的吗?';
        }

        setState(() {
          _isTyping = false;
          _messages.add({
            'id': 'resp_${DateTime.now().millisecondsSinceEpoch}',
            'role': 'assistant',
            'content': response,
            'timestamp': DateTime.now(),
          });
        });
        _scrollToBottom();
      }
    });
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _copyCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surfaceDark,
        border: Border(
          left: BorderSide(color: AppTheme.divider),
        ),
      ),
      child: Column(
        children: [
          // Header
          _buildHeader(),

          // Messages
          Expanded(
            child: Container(
              color: AppTheme.deepSpace.withOpacity(0.5),
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(12),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  final isUser = msg['role'] == 'user';
                  final isSystem = msg['role'] == 'system';

                  if (isSystem) return _buildSystemMessage(msg['content']);
                  return _buildMessageBubble(msg, isUser);
                },
              ),
            ),
          ),

          // Typing indicator
          if (_isTyping) _buildTypingIndicator(),

          // Quick actions
          if (!_isTyping) _buildQuickActions(),

          // Input bar
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: AppTheme.surfaceDark,
        border: Border(
          bottom: BorderSide(color: AppTheme.divider),
        ),
      ),
      child: Row(
        children: [
          // Resize handle
          Container(
            width: 3,
            height: 24,
            decoration: BoxDecoration(
              color: AppTheme.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),

          // AI icon
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              gradient: AppTheme.auroraGradient,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome, size: 14, color: Colors.white),
          ),
          const SizedBox(width: 8),

          // Title
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI 助手',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  'GPT-4',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ),

          // Model selector
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.tune, size: 18, color: AppTheme.textSecondary),
            tooltip: '设置',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),

          // Close button
          IconButton(
            onPressed: widget.onClose,
            icon: const Icon(Icons.close, size: 20, color: AppTheme.textSecondary),
            tooltip: '关闭',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemMessage(String content) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          content,
          style: const TextStyle(
            fontSize: 11,
            color: AppTheme.textTertiary,
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg, bool isUser) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.55,
        ),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: isUser ? AppTheme.auroraGradient : null,
          color: isUser ? null : AppTheme.surfaceCard,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(isUser ? 12 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 12),
          ),
          border: isUser
              ? null
              : Border.all(color: AppTheme.border.withOpacity(0.3)),
        ),
        child: _parseMessageContent(msg['content'] as String, isUser),
      ),
    );
  }

  Widget _parseMessageContent(String content, bool isUser) {
    final codePattern = RegExp(r'```(\w*)\n([\s\S]*?)```', multiLine: true);
    final matches = codePattern.allMatches(content);

    if (matches.isEmpty) {
      return SelectableText(
        content,
        style: TextStyle(
          fontSize: 13,
          color: isUser ? Colors.white : AppTheme.textPrimary,
          height: 1.5,
        ),
      );
    }

    final List<Widget> widgets = [];
    int lastEnd = 0;

    for (final match in matches) {
      if (match.start > lastEnd) {
        widgets.add(
          SelectableText(
            content.substring(lastEnd, match.start).trim(),
            style: TextStyle(
              fontSize: 13,
              color: isUser ? Colors.white : AppTheme.textPrimary,
              height: 1.5,
            ),
          ),
        );
      }

      final code = match.group(2) ?? '';
      widgets.add(_buildInlineCodeBlock(code));
      lastEnd = match.end;
    }

    if (lastEnd < content.length) {
      widgets.add(
        SelectableText(
          content.substring(lastEnd).trim(),
          style: TextStyle(
            fontSize: 13,
            color: isUser ? Colors.white : AppTheme.textPrimary,
            height: 1.5,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _buildInlineCodeBlock(String code) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.deepSpace,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Copy button
          InkWell(
            onTap: () => _copyCode(code),
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.copy,
                    size: 12,
                    color: AppTheme.textTertiary.withOpacity(0.7),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '复制',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppTheme.textTertiary.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Code
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: SelectableText(
              code,
              style: TextStyle(
                fontSize: 11,
                fontFamily: AppTheme.fontCode,
                color: AppTheme.textPrimary.withOpacity(0.9),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.surfaceCard,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(12),
            topRight: Radius.circular(12),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(12),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDot(0),
            const SizedBox(width: 4),
            _buildDot(1),
            const SizedBox(width: 4),
            _buildDot(2),
          ],
        ),
      ),
    );
  }

  Widget _buildDot(int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.3, end: 1.0),
      duration: Duration(milliseconds: 600 + (index * 150)),
      curve: Curves.easeInOut,
      builder: (context, value, child) {
        return Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: AppTheme.violet.withOpacity(value * 0.6),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }

  Widget _buildQuickActions() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _quickActions.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ActionChip(
              label: Text(
                _quickActions[index],
                style: const TextStyle(fontSize: 11),
              ),
              onPressed: () => _sendMessage(_quickActions[index]),
              backgroundColor: AppTheme.surfaceElevated,
              side: BorderSide(color: AppTheme.cyan.withOpacity(0.3)),
              labelStyle: const TextStyle(
                fontSize: 11,
                color: AppTheme.cyan,
              ),
              padding: EdgeInsets.zero,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          );
        },
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: const BoxDecoration(
        color: AppTheme.surfaceDark,
        border: Border(
          top: BorderSide(color: AppTheme.divider),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.surfaceElevated,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                      ),
                      decoration: const InputDecoration(
                        hintText: '输入消息...',
                        hintStyle: TextStyle(
                          color: AppTheme.textTertiary,
                          fontSize: 13,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _sendMessage(_messageController.text),
            child: Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                gradient: AppTheme.auroraGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send, size: 16, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
