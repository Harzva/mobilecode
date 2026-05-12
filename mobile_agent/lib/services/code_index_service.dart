import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

/// 代码索引服务 - 基于 SQLite FTS5 全文搜索
///
/// 管理项目代码文件的索引创建和查询，零外部依赖。
/// 使用 FTS5 虚拟表做全文匹配，普通表存文件内容。
class CodeIndexService {
  static final CodeIndexService _instance = CodeIndexService._internal();
  factory CodeIndexService() => _instance;
  CodeIndexService._internal();

  Database? _db;

  /// FTS5 虚拟表名 - 用于全文搜索
  static const String _ftsTable = 'code_index';

  /// 普通表名 - 用于快速读取文件内容
  static const String _filesTable = 'code_files';

  // ─────────────────────────────────────────────
  // 初始化
  // ─────────────────────────────────────────────

  /// 初始化 FTS5 虚拟表和普通文件表
  /// 应在应用启动时调用一次（如 main.dart 中）。
  Future<void> init(Database db) async {
    _db = db;
    try {
      // FTS5 虚拟表：project_id + file_path + content
      // 使用 'porter' 分词器支持英文词干提取
      await db.execute('''
        CREATE VIRTUAL TABLE IF NOT EXISTS $_ftsTable USING fts5(
          project_id,
          file_path,
          content,
          tokenize = 'porter unicode61'
        )
      ''');

      // 普通表：快速取文件内容，避免查 FTS 辅助表
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $_filesTable (
          project_id TEXT NOT NULL,
          file_path TEXT NOT NULL,
          content TEXT NOT NULL,
          last_modified INTEGER NOT NULL,
          PRIMARY KEY (project_id, file_path)
        )
      ''');

      // 给普通表加索引，加速按项目查文件列表
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_code_files_project 
        ON $_filesTable(project_id)
      ''');

      debugPrint('[CodeIndexService] FTS5 + code_files 表初始化完成');
    } catch (e, st) {
      debugPrint('[CodeIndexService] 初始化失败: $e');
      debugPrint('$st');
    }
  }

  // ─────────────────────────────────────────────
  // 索引操作
  // ─────────────────────────────────────────────

  /// 索引单个文件（路径 + 内容）。
  /// 如果文件已存在，先删除旧索引再插入新数据。
  Future<void> indexFile(
    String projectId,
    String filePath,
    String content,
  ) async {
    if (_db == null) {
      debugPrint('[CodeIndexService] 未初始化，跳过索引');
      return;
    }
    try {
      final db = _db!;
      final now = DateTime.now().millisecondsSinceEpoch;

      // 删除旧索引（FTS5 不支持 REPLACE，手动删）
      await db.delete(
        _ftsTable,
        where: 'project_id = ? AND file_path = ?',
        whereArgs: [projectId, filePath],
      );
      await db.delete(
        _filesTable,
        where: 'project_id = ? AND file_path = ?',
        whereArgs: [projectId, filePath],
      );

      // 插入 FTS5 索引
      await db.insert(_ftsTable, {
        'project_id': projectId,
        'file_path': filePath,
        'content': content,
      });

      // 插入普通表
      await db.insert(_filesTable, {
        'project_id': projectId,
        'file_path': filePath,
        'content': content,
        'last_modified': now,
      });

      debugPrint('[CodeIndexService] 索引完成: $filePath');
    } catch (e, st) {
      debugPrint('[CodeIndexService] 索引文件失败 [$filePath]: $e');
      debugPrint('$st');
    }
  }

  /// 批量索引项目所有文件。
  /// 使用事务包裹，batchSize = 50，失败时整批回滚。
  Future<void> indexProject(
    String projectId,
    List<ProjectFile> files,
  ) async {
    if (_db == null) {
      debugPrint('[CodeIndexService] 未初始化，跳过批量索引');
      return;
    }
    if (files.isEmpty) return;

    try {
      final db = _db!;
      const int batchSize = 50;
      int successCount = 0;

      await db.transaction((txn) async {
        for (int i = 0; i < files.length; i += batchSize) {
          final end = (i + batchSize < files.length) ? i + batchSize : files.length;
          final batch = files.sublist(i, end);

          for (final file in batch) {
            final now = DateTime.now().millisecondsSinceEpoch;

            // 删除旧索引
            await txn.delete(
              _ftsTable,
              where: 'project_id = ? AND file_path = ?',
              whereArgs: [projectId, file.path],
            );
            await txn.delete(
              _filesTable,
              where: 'project_id = ? AND file_path = ?',
              whereArgs: [projectId, file.path],
            );

            // 插入新索引
            await txn.insert(_ftsTable, {
              'project_id': projectId,
              'file_path': file.path,
              'content': file.content,
            });
            await txn.insert(_filesTable, {
              'project_id': projectId,
              'file_path': file.path,
              'content': file.content,
              'last_modified': now,
            });

            successCount++;
          }
        }
      });

      debugPrint(
        '[CodeIndexService] 批量索引完成: $projectId, 共 ${files.length} 个文件, 成功 $successCount 个',
      );
    } catch (e, st) {
      debugPrint('[CodeIndexService] 批量索引失败 [$projectId]: $e');
      debugPrint('$st');
    }
  }

  /// 删除指定项目的所有索引数据。
  Future<void> clearProjectIndex(String projectId) async {
    if (_db == null) return;
    try {
      final db = _db!;
      await db.delete(
        _ftsTable,
        where: 'project_id = ?',
        whereArgs: [projectId],
      );
      await db.delete(
        _filesTable,
        where: 'project_id = ?',
        whereArgs: [projectId],
      );
      debugPrint('[CodeIndexService] 已清除项目索引: $projectId');
    } catch (e, st) {
      debugPrint('[CodeIndexService] 清除索引失败 [$projectId]: $e');
      debugPrint('$st');
    }
  }

  // ─────────────────────────────────────────────
  // 搜索
  // ─────────────────────────────────────────────

  /// 全文搜索，返回相关文件路径列表（按 FTS5 rank 排序）。
  ///
  /// [keywords] 为关键词列表，内部用 AND 拼接成 FTS5 MATCH 查询。
  /// [limit] 最多返回几条结果，默认 5。
  Future<List<IndexedFile>> search(
    String projectId,
    List<String> keywords, {
    int limit = 5,
  }) async {
    if (_db == null || keywords.isEmpty) return [];

    try {
      final db = _db!;

      // 清理关键词，防止注入：只保留字母数字中文下划线
      final safeKeywords = keywords.map(_escapeKeyword).where((k) => k.isNotEmpty).toList();
      if (safeKeywords.isEmpty) return [];

      // FTS5 MATCH 语法：keyword1 AND keyword2 AND ...
      final matchQuery = safeKeywords.join(' AND ');

      final rows = await db.rawQuery('''
        SELECT file_path, content, rank 
        FROM $_ftsTable 
        WHERE project_id = ? AND content MATCH ?
        ORDER BY rank ASC
        LIMIT ?
      ''', [projectId, matchQuery, limit]);

      final results = <IndexedFile>[];
      for (final row in rows) {
        final filePath = row['file_path'] as String? ?? '';
        final content = row['content'] as String? ?? '';
        final rankValue = row['rank'] as num? ?? 0;

        // 生成匹配内容预览（前 200 字符）
        final preview = content.length > 200 ? content.substring(0, 200) : content;

        results.add(IndexedFile(
          filePath: filePath,
          preview: preview,
          rank: rankValue.toDouble(),
        ));
      }

      debugPrint(
        '[CodeIndexService] 搜索 [$projectId] 关键词=${safeKeywords.join(',')} 返回 ${results.length} 条',
      );
      return results;
    } catch (e, st) {
      debugPrint('[CodeIndexService] 搜索失败 [$projectId]: $e');
      debugPrint('$st');
      return [];
    }
  }

  // ─────────────────────────────────────────────
  // 辅助查询
  // ─────────────────────────────────────────────

  /// 获取项目下所有文件路径列表。
  Future<List<String>> getProjectFiles(String projectId) async {
    if (_db == null) return [];
    try {
      final db = _db!;
      final rows = await db.query(
        _filesTable,
        columns: ['file_path'],
        where: 'project_id = ?',
        whereArgs: [projectId],
        orderBy: 'file_path ASC',
      );
      return rows.map((r) => r['file_path'] as String).toList();
    } catch (e, st) {
      debugPrint('[CodeIndexService] 获取文件列表失败 [$projectId]: $e');
      debugPrint('$st');
      return [];
    }
  }

  /// 根据路径获取文件内容。
  /// 返回 null 表示文件不存在。
  Future<String?> getFileContent(String projectId, String filePath) async {
    if (_db == null) return null;
    try {
      final db = _db!;
      final rows = await db.query(
        _filesTable,
        columns: ['content'],
        where: 'project_id = ? AND file_path = ?',
        whereArgs: [projectId, filePath],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return rows.first['content'] as String?;
    } catch (e, st) {
      debugPrint('[CodeIndexService] 获取文件内容失败 [$filePath]: $e');
      debugPrint('$st');
      return null;
    }
  }

  // ─────────────────────────────────────────────
  // 工具方法
  // ─────────────────────────────────────────────

  /// 转义关键词，保留字母数字和中文字符，其余丢弃。
  String _escapeKeyword(String keyword) {
    final buffer = StringBuffer();
    for (final ch in keyword.runes) {
      final c = String.fromCharCode(ch);
      // 字母数字下划线中文
      if (RegExp(r'[a-zA-Z0-9_\u4e00-\u9fff]').hasMatch(c)) {
        buffer.write(c);
      }
    }
    return buffer.toString().trim();
  }
}

// ─────────────────────────────────────────────
// 数据模型
// ─────────────────────────────────────────────

/// 搜索结果模型
class IndexedFile {
  final String filePath;
  final String? preview;
  final double rank;

  const IndexedFile({
    required this.filePath,
    this.preview,
    required this.rank,
  });

  @override
  String toString() => 'IndexedFile($filePath, rank=$rank)';
}

/// 项目文件模型
class ProjectFile {
  final String path;
  final String content;

  const ProjectFile({
    required this.path,
    required this.content,
  });
}
