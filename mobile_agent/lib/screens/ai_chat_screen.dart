import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../themes/app_theme.dart';

/// AI Assistant Chat Screen
/// WhatsApp-like chat interface with code blocks, typing indicator, quick actions
class AiChatScreen extends StatefulWidget {
  final String? initialCode;
  final String? fileName;

  const AiChatScreen({
    super.key,
    this.initialCode,
    this.fileName,
  });

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  bool _isTyping = false;
  String _selectedModel = 'GPT-4';

  final List<String> _quickActions = [
    '解释代码',
    '修复错误',
    '优化代码',
    '添加注释',
    '生成测试',
    '转换语言',
  ];

  @override
  void initState() {
    super.initState();
    // Add welcome message
    _messages.add({
      'id': 'welcome',
      'role': 'assistant',
      'content': '你好！我是 Mobile Agent 的 AI 助手。我可以帮你解释代码、修复错误、优化性能，或者回答任何编程相关的问题。',
      'timestamp': DateTime.now(),
      'codeBlocks': [],
    });

    // If code is provided, add context message
    if (widget.initialCode != null) {
      _messages.add({
        'id': 'context',
        'role': 'user',
        'content': '请帮我看看这段${widget.fileName != null ? '来自 ${widget.fileName} 的' : ''}代码：\n\n```\n${widget.initialCode!.length > 500 ? widget.initialCode!.substring(0, 500) + '...' : widget.initialCode}\n```',
        'timestamp': DateTime.now(),
        'codeBlocks': [widget.initialCode],
      });
    }
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
        'codeBlocks': [],
      });
      _isTyping = true;
    });

    _messageController.clear();
    _scrollToBottom();

    // Simulate AI response
    _simulateAIResponse(content);
  }

  Future<void> _simulateAIResponse(String userMessage) async {
    await Future.delayed(const Duration(seconds: 1));

    String response;
    if (userMessage.contains('解释') || userMessage.contains('explain')) {
      response = '''这段代码的核心逻辑如下：

1. **初始化阶段**：设置必要的配置和状态
2. **主循环**：处理输入并更新状态
3. **清理阶段**：释放资源并保存状态

主要使用了以下设计模式：
- 单例模式 (Singleton)
- 观察者模式 (Observer)
- 工厂模式 (Factory)

如果你有具体的疑问，欢迎继续提问！'''; // Closing triple-quote
    } else if (userMessage.contains('修复') || userMessage.contains('fix')) {
      response = '''我发现了一个潜在的问题。这里是修复后的代码：

```dart
// 修复后的版本
class FixedVersion {
  final String name;
  final int count;
  
  FixedVersion({
    required this.name,
    this.count = 0, // 添加默认值
  });
  
  // 添加空值检查
  String get displayName => name.isEmpty ? 'Unknown' : name;
}
```

主要修复点：
1. 添加了默认值防止 null 错误
2. 增加了空值检查
3. 改进了错误处理'''; // Closing triple-quote
    } else if (userMessage.contains('优化') || userMessage.contains('optimize')) {
      response = '''以下是几个优化建议：

```dart
// 优化前
List<int> processData(List<int> data) {
  var result = [];
  for (var i = 0; i < data.length; i++) {
    if (data[i] > 0) {
      result.add(data[i] * 2);
    }
  }
  return result;
}

// 优化后 - 使用函数式编程
List<int> processData(List<int> data) => data
  .where((x) => x > 0)
  .map((x) => x * 2)
  .toList();
```

**性能提升**：
- 时间复杂度从 O(n) 优化到 O(n)
- 内存分配减少了约 40%
- 代码可读性显著提升'''; // Closing triple-quote
    } else {
      response = '''这是一个很好的问题！让我来帮你分析：

根据代码的结构和上下文，我建议采用以下方案：

1. **重构核心逻辑**：将复杂的条件判断提取为独立函数
2. **增加单元测试**：确保重构后的代码行为一致
3. **文档注释**：为公共 API 添加 dartdoc 注释

```dart
/// 处理用户输入的核心函数
/// 
/// [input] 用户输入的原始字符串
/// 返回处理后的结果，如果输入无效则返回 null
String? processInput(String input) {
  if (input.trim().isEmpty) return null;
  
  return input
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'\s+'), ' ');
}
```

还有什么我可以帮你的吗？'''; // Closing triple-quote
    }

    if (mounted) {
      setState(() {
        _isTyping = false;
        _messages.add({
          'id': 'resp_${DateTime.now().millisecondsSinceEpoch}',
          'role': 'assistant',
          'content': response,
          'timestamp': DateTime.now(),
          'codeBlocks': _extractCodeBlocks(response),
        });
      });
      _scrollToBottom();
    }
  }

  List<String> _extractCodeBlocks(String content) {
    final List<String> blocks = [];
    final RegExp pattern = RegExp(r'```[\w]*\n([\s\S]*?)```', multiLine: true);
    for (final match in pattern.allMatches(content)) {
      blocks.add(match.group(1) ?? '');
    }
    return blocks;
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

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制到剪贴板'),
        duration: Duration(seconds: 1),
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
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: AppTheme.textSecondary),
        ),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                gradient: AppTheme.auroraGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome, size: 18, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'AI 助手',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppTheme.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _isTyping ? '正在输入...' : '在线',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppTheme.textSecondary),
            color: AppTheme.surfaceElevated,
            onSelected: (value) {
              if (value == 'clear') {
                setState(() => _messages.clear());
              } else if (value == 'model') {
                _showModelSelector();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'model',
                child: Row(
                  children: [
                    const Icon(Icons.model_training, size: 18, color: AppTheme.textSecondary),
                    const SizedBox(width: 10),
                    Text('模型: $_selectedModel', style: const TextStyle(color: AppTheme.textPrimary)),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 18, color: AppTheme.error),
                    SizedBox(width: 10),
                    Text('清空对话', style: TextStyle(color: AppTheme.error)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final isUser = message['role'] == 'user';
                return _buildMessageBubble(message, isUser);
              },
            ),
          ),

          // Typing indicator
          if (_isTyping) _buildTypingIndicator(),

          // Quick action chips
          if (!_isTyping) _buildQuickActions(),

          // Input bar
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> message, bool isUser) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: isUser ? AppTheme.auroraGradient : null,
                color: isUser ? null : AppTheme.surfaceCard,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
                border: isUser
                    ? null
                    : Border.all(
                        color: AppTheme.border.withOpacity(0.3),
                      ),
              ),
              child: _buildMessageContent(message['content'] as String, isUser),
            ),
            const SizedBox(height: 2),
            Text(
              _formatTime(message['timestamp'] as DateTime),
              style: const TextStyle(fontSize: 10, color: AppTheme.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageContent(String content, bool isUser) {
    // Parse code blocks
    final codePattern = RegExp(r'```(\w*)\n([\s\S]*?)```', multiLine: true);
    final matches = codePattern.allMatches(content);

    if (matches.isEmpty) {
      return SelectableText(
        content,
        style: TextStyle(
          fontSize: 14,
          color: isUser ? Colors.white : AppTheme.textPrimary,
          height: 1.5,
        ),
      );
    }

    // Build content with code blocks
    final List<Widget> widgets = [];
    int lastEnd = 0;

    for (final match in matches) {
      // Text before code block
      if (match.start > lastEnd) {
        widgets.add(SelectableText(
          content.substring(lastEnd, match.start).trim(),
          style: TextStyle(
            fontSize: 14,
            color: isUser ? Colors.white : AppTheme.textPrimary,
            height: 1.5,
          ),
        ));
      }

      // Code block
      final language = match.group(1) ?? 'text';
      final code = match.group(2) ?? '';
      widgets.add(_buildCodeBlock(code, language));

      lastEnd = match.end;
    }

    // Remaining text
    if (lastEnd < content.length) {
      widgets.add(SelectableText(
        content.substring(lastEnd).trim(),
        style: TextStyle(
          fontSize: 14,
          color: isUser ? Colors.white : AppTheme.textPrimary,
          height: 1.5,
        ),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _buildCodeBlock(String code, String language) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.deepSpace,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Code header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: const BoxDecoration(
              color: AppTheme.surfaceElevated,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
            ),
            child: Row(
              children: [
                Text(
                  language.isEmpty ? 'code' : language,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textTertiary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _copyToClipboard(code),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
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
                              fontSize: 11,
                              color: AppTheme.textTertiary.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Code content
          Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              code,
              style: TextStyle(
                fontSize: 12,
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.surfaceCard,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          ),
          border: Border.all(color: AppTheme.border.withOpacity(0.3)),
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: AppTheme.violet.withOpacity(0.5 + (index * 0.15)),
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _buildQuickActions() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _quickActions.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ActionChip(
              label: Text(_quickActions[index]),
              onPressed: () => _sendMessage(_quickActions[index]),
              backgroundColor: AppTheme.surfaceElevated,
              labelStyle: const TextStyle(
                fontSize: 12,
                color: AppTheme.cyan,
              ),
              side: BorderSide(color: AppTheme.cyan.withOpacity(0.3)),
              padding: EdgeInsets.zero,
            ),
          );
        },
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: AppTheme.surfaceDark,
        border: Border(
          top: BorderSide(color: AppTheme.divider),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.attach_file, color: AppTheme.textTertiary),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                        ),
                        decoration: const InputDecoration(
                          hintText: '输入消息...',
                          hintStyle: TextStyle(color: AppTheme.textTertiary),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                        textInputAction: TextInputAction.send,
                        onSubmitted: _sendMessage,
                      ),
                    ),
                    if (_messageController.text.isNotEmpty)
                      IconButton(
                        onPressed: () => _messageController.clear(),
                        icon: const Icon(Icons.clear, size: 18),
                        color: AppTheme.textTertiary,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
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
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  gradient: AppTheme.auroraGradient,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.send,
                  size: 18,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showModelSelector() {
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
                '选择模型',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              ...['GPT-4', 'Claude 3.5', 'Gemini Pro', 'DeepSeek'].map((model) =>
                  ListTile(
                    leading: Icon(
                      Icons.psychology,
                      color: _selectedModel == model
                          ? AppTheme.violetLight
                          : AppTheme.textSecondary,
                    ),
                    title: Text(
                      model,
                      style: TextStyle(
                        color: _selectedModel == model
                            ? AppTheme.textPrimary
                            : AppTheme.textSecondary,
                        fontWeight: _selectedModel == model
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                    trailing: _selectedModel == model
                        ? const Icon(Icons.check, color: AppTheme.violetLight)
                        : null,
                    onTap: () {
                      setState(() => _selectedModel = model);
                      Navigator.pop(context);
                    },
                  )),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
