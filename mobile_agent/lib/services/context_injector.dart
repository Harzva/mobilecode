import 'package:flutter/foundation.dart';
import 'code_index_service.dart';

/// 上下文注入器 - 自动从用户消息提取关键词并注入相关代码上下文
///
/// 职责：
/// 1. 从用户消息提取中英文关键词（简单字符扫描，零 NLP 依赖）
/// 2. 调用 CodeIndexService 搜索相关代码文件
/// 3. 将代码上下文拼接成 AI Prompt
///
/// 使用方式：
/// ```dart
/// final prompt = await contextInjector.buildContextPrompt('proj_1', '帮我改登录页');
/// // 将 prompt 附加到 AI 请求中
/// ```
class ContextInjector {
  final CodeIndexService _codeIndex;

  ContextInjector({CodeIndexService? codeIndexService})
      : _codeIndex = codeIndexService ?? CodeIndexService();

  // ─────────────────────────────────────────────
  // 停用词表
  // ─────────────────────────────────────────────

  /// 中文停用词 - 逐字符扫描时过滤
  static const Set<String> _cnStopWords = {
    '的', '了', '是', '在', '我', '有', '和', '就', '不', '人', '都',
    '一', '一个', '上', '也', '很', '到', '说', '要', '去', '你', '会',
    '着', '没有', '看', '好', '自己', '这', '那', '里', '个', '帮', '改',
    '修', '加', '删', '查', '找', '写', '用', '怎么', '如何', '为什么', '请问',
  };

  /// 英文停用词 - 按空格分词后过滤
  static const Set<String> _enStopWords = {
    'the', 'a', 'an', 'is', 'are', 'was', 'were', 'be', 'been', 'being',
    'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would', 'could',
    'should', 'may', 'might', 'must', 'shall', 'can', 'need', 'help', 'fix',
    'change', 'add', 'delete', 'remove', 'search', 'find', 'write', 'use',
    'how', 'what', 'why', 'please', 'to', 'of', 'in', 'for', 'on', 'with',
    'at', 'by', 'from', 'as', 'it', 'this', 'that', 'my', 'me',
  };

  // ─────────────────────────────────────────────
  // 关键词提取
  // ─────────────────────────────────────────────

  /// 从用户消息中提取关键词（中英文混合）。
  ///
  /// 算法：
  /// 1. 中文：逐字符扫描，连续中文字符组成词，过滤停用词
  /// 2. 英文：按空格分词，过滤停用词
  /// 3. 保留长度 >= 2 的词
  /// 4. 最多返回 6 个关键词
  static List<String> extractKeywords(String message) {
    if (message.trim().isEmpty) return [];

    final keywords = <String>[];
    final buffer = StringBuffer();

    for (int i = 0; i < message.length; i++) {
      final ch = message[i];
      final code = ch.codeUnitAt(0);

      // 中文字符范围 \u4e00-\u9fff
      final isChinese = (code >= 0x4E00 && code <= 0x9FFF);
      // 英文字母
      final isEnglish = (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A);
      // 数字（英文词的一部分）
      final isDigit = (code >= 0x30 && code <= 0x39);
      // 下划线（标识符的一部分）
      final isUnderscore = (ch == '_');

      if (isChinese) {
        // 如果缓冲区里有英文内容，先处理
        if (buffer.isNotEmpty) {
          _flushEnglish(buffer, keywords);
          buffer.clear();
        }
        // 中文字符直接作为独立词（长度至少为1，因为汉字本身有意义）
        final word = ch;
        if (word.length >= 2 || !_cnStopWords.contains(word)) {
          if (!_cnStopWords.contains(word)) {
            keywords.add(word);
          }
        }
      } else if (isEnglish || isDigit || isUnderscore) {
        // 英文、数字、下划线累积
        buffer.write(ch.toLowerCase());
      } else {
        // 其他字符（空格、标点等）作为英文分词边界
        if (buffer.isNotEmpty) {
          _flushEnglish(buffer, keywords);
          buffer.clear();
        }
      }
    }

    // 处理尾部残留的英文
    if (buffer.isNotEmpty) {
      _flushEnglish(buffer, keywords);
    }

    // 去重并保持顺序
    final seen = <String>{};
    final unique = <String>[];
    for (final kw in keywords) {
      if (seen.add(kw)) {
        unique.add(kw);
      }
    }

    // 最多返回 6 个
    if (unique.length > 6) {
      return unique.sublist(0, 6);
    }
    return unique;
  }

  /// 将缓冲区中的英文词提取到结果列表
  static void _flushEnglish(StringBuffer buffer, List<String> keywords) {
    final word = buffer.toString().trim();
    if (word.length >= 2 && !_enStopWords.contains(word)) {
      keywords.add(word);
    }
  }

  // ─────────────────────────────────────────────
  // 上下文 Prompt 构建
  // ─────────────────────────────────────────────

  /// 根据用户消息构建上下文 Prompt。
  ///
  /// 流程：
  /// 1. extractKeywords 提取关键词
  /// 2. CodeIndexService.search 搜索相关文件
  /// 3. 取前 3 个最相关的文件
  /// 4. 每个文件最多取前 50 行
  /// 5. 拼接成标准格式的上下文
  Future<String> buildContextPrompt(String projectId, String userMessage) async {
    try {
      // 1. 提取关键词
      final keywords = extractKeywords(userMessage);
      if (keywords.isEmpty) {
        debugPrint('[ContextInjector] 未提取到关键词，不注入上下文');
        return '';
      }
      debugPrint('[ContextInjector] 关键词: ${keywords.join(', ')}');

      // 2. 搜索相关文件
      final results = await _codeIndex.search(projectId, keywords, limit: 3);
      if (results.isEmpty) {
        debugPrint('[ContextInjector] 未找到相关代码文件');
        return '';
      }

      // 3. 拼接上下文
      final buffer = StringBuffer();
      buffer.writeln('以下是项目中与你问题相关的代码文件：');
      buffer.writeln();

      for (final indexedFile in results) {
        final content = await _codeIndex.getFileContent(
              projectId,
              indexedFile.filePath,
            ) ??
            indexedFile.preview ??
            '';

        // 取前 50 行
        final limitedContent = _takeFirstNLines(content, 50);

        buffer.writeln('### 文件: ${indexedFile.filePath}');
        buffer.writeln('```dart');
        buffer.writeln(limitedContent);
        if (content.split('\n').length > 50) {
          buffer.writeln('...');
        }
        buffer.writeln('```');
        buffer.writeln();
      }

      buffer.writeln('请基于以上代码回答用户问题。');

      final prompt = buffer.toString();
      debugPrint(
        '[ContextInjector] 上下文构建完成: ${results.length} 个文件, ${prompt.length} 字符',
      );
      return prompt;
    } catch (e, st) {
      debugPrint('[ContextInjector] 构建上下文失败: $e');
      debugPrint('$st');
      return '';
    }
  }

  // ─────────────────────────────────────────────
  // 项目结构摘要
  // ─────────────────────────────────────────────

  /// 构建项目结构摘要，让 AI 了解项目概况。
  ///
  /// 格式：
  /// ```
  /// 项目结构：共 X 个文件
  /// - Dart 文件: X 个
  /// - 配置文件: X 个
  /// 关键目录: lib/, lib/screens/, lib/services/
  /// ```
  Future<String> buildProjectSummary(String projectId) async {
    try {
      final files = await _codeIndex.getProjectFiles(projectId);
      if (files.isEmpty) {
        return '项目结构：暂无文件';
      }

      // 统计文件类型
      int dartCount = 0;
      int configCount = 0;
      int otherCount = 0;
      final dirSet = <String>{};

      for (final path in files) {
        // 统计扩展名
        if (path.endsWith('.dart')) {
          dartCount++;
        } else if (path.endsWith('.yaml') ||
            path.endsWith('.yml') ||
            path.endsWith('.json') ||
            path.endsWith('.xml') ||
            path.endsWith('.gradle') ||
            path.endsWith('.plist') ||
            path.endsWith('.properties')) {
          configCount++;
        } else {
          otherCount++;
        }

        // 提取目录
        final lastSlash = path.lastIndexOf('/');
        if (lastSlash > 0) {
          dirSet.add(path.substring(0, lastSlash + 1));
        }
      }

      // 选择最关键的目录（最多 5 个，按文件数量排序）
      final dirFileCount = <String, int>{};
      for (final dir in dirSet) {
        dirFileCount[dir] = files.where((f) => f.startsWith(dir)).length;
      }
      final sortedDirs = dirFileCount.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final topDirs = sortedDirs.take(5).map((e) => e.key).toList();

      final buffer = StringBuffer();
      buffer.writeln('项目结构：共 ${files.length} 个文件');
      if (dartCount > 0) buffer.writeln('- Dart 文件: $dartCount 个');
      if (configCount > 0) buffer.writeln('- 配置文件: $configCount 个');
      if (otherCount > 0) buffer.writeln('- 其他文件: $otherCount 个');
      if (topDirs.isNotEmpty) {
        buffer.writeln('关键目录: ${topDirs.join(', ')}');
      }

      return buffer.toString().trim();
    } catch (e, st) {
      debugPrint('[ContextInjector] 构建项目摘要失败: $e');
      debugPrint('$st');
      return '项目结构：获取失败';
    }
  }

  // ─────────────────────────────────────────────
  // 工具方法
  // ─────────────────────────────────────────────

  /// 取字符串的前 N 行。
  static String _takeFirstNLines(String content, int n) {
    final lines = content.split('\n');
    if (lines.length <= n) return content;
    return lines.sublist(0, n).join('\n');
  }
}
