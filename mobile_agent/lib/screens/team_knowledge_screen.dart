import 'package:flutter/material.dart';
import '../themes/app_theme.dart';
import '../widgets/glass_card_widget.dart';
import '../widgets/gradient_button_widget.dart';

/// Team Knowledge Screen - Team knowledge base / wiki system
/// Features: categories, article list, article detail, create/edit,
/// comments, bookmarks, search
class TeamKnowledgeScreen extends StatefulWidget {
  const TeamKnowledgeScreen({super.key});

  @override
  State<TeamKnowledgeScreen> createState() => _TeamKnowledgeScreenState();
}

class KnowledgeArticle {
  final String id;
  final String title;
  final String content;
  final String preview;
  final String author;
  final String authorInitials;
  final String category;
  final List<String> tags;
  final int viewCount;
  final int likeCount;
  final int commentCount;
  final DateTime createdAt;
  final bool isPinned;
  bool isBookmarked;
  bool isLiked;

  KnowledgeArticle({
    required this.id,
    required this.title,
    required this.content,
    required this.preview,
    required this.author,
    required this.authorInitials,
    required this.category,
    required this.tags,
    this.viewCount = 0,
    this.likeCount = 0,
    this.commentCount = 0,
    required this.createdAt,
    this.isPinned = false,
    this.isBookmarked = false,
    this.isLiked = false,
  });
}

class Comment {
  final String id;
  final String author;
  final String authorInitials;
  final String content;
  final DateTime createdAt;

  Comment({
    required this.id,
    required this.author,
    required this.authorInitials,
    required this.content,
    required this.createdAt,
  });
}

class _TeamKnowledgeScreenState extends State<TeamKnowledgeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final List<KnowledgeArticle> _articles = [];
  final List<Comment> _comments = [];
  String _selectedCategory = '全部';
  String _searchQuery = '';
  int _draftCount = 3;

  final List<String> _categories = [
    '全部',
    '代码规范',
    '架构设计',
    'API文档',
    '部署指南',
    '常见问题',
    '最佳实践',
    '会议纪要',
  ];

  @override
  void initState() {
    super.initState();
    _loadArticles();
    _loadComments();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadArticles() {
    _articles.addAll([
      KnowledgeArticle(
        id: '1',
        title: 'Flutter 项目代码规范 V2.0',
        content: '''## Flutter 项目代码规范 V2.0

### 1. 命名规范

- 文件命名：使用小写下划线命名法（snake_case）
- 类命名：使用大驼峰命名法（PascalCase）
- 变量命名：使用小驼峰命名法（camelCase）
- 常量命名：使用全大写下划线命名法（SCREAMING_SNAKE_CASE）

### 2. 代码结构

每个文件应该按以下顺序组织：
1. 导入语句
2. 常量定义
3. 类/函数定义
4. 私有辅助函数

### 3. Widget 构建规范

- 使用 const 构造函数
- 拆分复杂 Widget 为子方法
- 避免深层嵌套（最大 4 层）

### 4. 状态管理

- 优先使用 StatefulWidget
- 共享状态使用 Provider 或 Riverpod
- 避免在 build 方法中执行副作用操作''',
        preview: '本文档定义了 Flutter 项目的代码规范，包括命名规范、代码结构、Widget 构建规范和状态管理指南...',
        author: '张明',
        authorInitials: 'ZM',
        category: '代码规范',
        tags: ['Flutter', 'Dart', '规范'],
        viewCount: 342,
        likeCount: 56,
        commentCount: 8,
        createdAt: DateTime.now().subtract(const Duration(days: 30)),
        isPinned: true,
      ),
      KnowledgeArticle(
        id: '2',
        title: '移动端架构设计指南',
        content: '''## 移动端架构设计指南

### 架构概述

我们采用 Clean Architecture + MVVM 的混合架构模式。

### 分层结构

```
lib/
  core/          # 核心层
    theme/       # 主题配置
    constants/   # 常量定义
  data/          # 数据层
    models/      # 数据模型
    repositories/# 数据仓库
  domain/        # 领域层
    usecases/    # 用例
    entities/    # 实体
  presentation/  # 表现层
    screens/     # 页面
    widgets/     # 组件
    viewmodels/  # 视图模型
```

### 依赖规则

内层不依赖外层，外层依赖内层。数据流向单一方向。''',
        preview: '本文介绍了移动端的架构设计方案，采用 Clean Architecture + MVVM 混合架构模式...',
        author: '李华',
        authorInitials: 'LH',
        category: '架构设计',
        tags: ['架构', 'Clean Architecture', 'MVVM'],
        viewCount: 256,
        likeCount: 42,
        commentCount: 5,
        createdAt: DateTime.now().subtract(const Duration(days: 20)),
        isPinned: true,
      ),
      KnowledgeArticle(
        id: '3',
        title: 'RESTful API 接口文档',
        content: '''## RESTful API 接口文档

### 基础信息

- 基础 URL: `https://api.example.com/v1`
- 认证方式: Bearer Token
- Content-Type: `application/json`

### 认证接口

#### POST /auth/login

用户登录接口。

**请求参数：**
```json
{
  "email": "user@example.com",
  "password": "your_password"
}
```

**响应：**
```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user": {
    "id": "123",
    "name": "用户名",
    "email": "user@example.com"
  }
}
```

### 错误码

| 状态码 | 说明 |
|--------|------|
| 200 | 成功 |
| 400 | 请求参数错误 |
| 401 | 未授权 |
| 403 | 禁止访问 |
| 500 | 服务器内部错误 |''',
        preview: '完整的 RESTful API 接口文档，包含认证接口、请求参数、响应格式和错误码说明...',
        author: '王芳',
        authorInitials: 'WF',
        category: 'API文档',
        tags: ['API', 'REST', '后端'],
        viewCount: 189,
        likeCount: 28,
        commentCount: 3,
        createdAt: DateTime.now().subtract(const Duration(days: 15)),
      ),
      KnowledgeArticle(
        id: '4',
        title: 'iOS & Android 部署流程',
        content: '''## iOS & Android 部署流程

### Android 部署

1. 更新版本号
2. 构建 Release APK
3. 签名 APK
4. 上传到 Google Play

### iOS 部署

1. 更新版本号和 Build 号
2. 构建 Archive
3. 上传到 App Store Connect
4. 提交审核

### Flutter 热更新

使用 CodePush 进行热更新部署。''',
        preview: '详细的 iOS 和 Android 应用部署流程文档，包含 Flutter 热更新方案...',
        author: '赵强',
        authorInitials: 'ZQ',
        category: '部署指南',
        tags: ['部署', 'iOS', 'Android'],
        viewCount: 145,
        likeCount: 22,
        commentCount: 4,
        createdAt: DateTime.now().subtract(const Duration(days: 10)),
      ),
      KnowledgeArticle(
        id: '5',
        title: '常见问题解决方案汇总',
        content: '''## 常见问题解决方案

### Flutter 构建问题

**问题：构建卡在 "Running Gradle task"**

解决方案：
```bash
flutter clean
flutter pub get
cd android && ./gradlew clean
```

**问题：iOS 模拟器无法启动**

解决方案：
```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
```''',
        preview: '汇总了开发过程中常见的问题和解决方案，包括 Flutter 构建问题和 iOS 模拟器问题...',
        author: '钱丽',
        authorInitials: 'QL',
        category: '常见问题',
        tags: ['FAQ', '问题排查', '调试'],
        viewCount: 678,
        likeCount: 89,
        commentCount: 12,
        createdAt: DateTime.now().subtract(const Duration(days: 7)),
        isPinned: true,
      ),
      KnowledgeArticle(
        id: '6',
        title: '性能优化最佳实践',
        content: '''## 性能优化最佳实践

### 1. Widget 优化

- 使用 const 构造函数
- 使用 RepaintBoundary 隔离重绘
- 避免不必要的 setState

### 2. 列表优化

- 使用 ListView.builder
- 设置 itemExtent
- 使用缓存图片

### 3. 内存优化

- 及时释放图片资源
- 使用 WeakReference
- 避免内存泄漏''',
        preview: '整理了 Flutter 应用的性能优化最佳实践，涵盖 Widget 优化、列表优化和内存优化...',
        author: '孙伟',
        authorInitials: 'SW',
        category: '最佳实践',
        tags: ['性能', '优化', '最佳实践'],
        viewCount: 234,
        likeCount: 45,
        commentCount: 6,
        createdAt: DateTime.now().subtract(const Duration(days: 5)),
      ),
      KnowledgeArticle(
        id: '7',
        title: '2024年第四季度会议纪要',
        content: '''## Q4 会议纪要

### 参会人员
张明、李华、王芳、赵强、钱丽、孙伟

### 议题
1. 回顾 Q4 完成情况
2. Q1 2025 目标设定
3. 技术栈升级讨论

### 决议
- 升级到 Flutter 3.24
- 引入 Riverpod 状态管理
- 建立代码审查流程''',
        preview: '2024年第四季度团队会议纪要，包含参会人员、讨论议题和决议事项...',
        author: '周敏',
        authorInitials: 'ZM',
        category: '会议纪要',
        tags: ['会议', '规划', '团队'],
        viewCount: 98,
        likeCount: 15,
        commentCount: 2,
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
      ),
    ]);
  }

  void _loadComments() {
    _comments.addAll([
      Comment(
        id: 'c1',
        author: '张明',
        authorInitials: 'ZM',
        content: '写得非常详细，建议补充关于空安全的部分',
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      ),
      Comment(
        id: 'c2',
        author: '李华',
        authorInitials: 'LH',
        content: '已更新，增加了空安全检查的内容',
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      ),
    ]);
  }

  List<KnowledgeArticle> get _filteredArticles {
    var result = _articles;
    if (_selectedCategory != '全部') {
      result = result.where((a) => a.category == _selectedCategory).toList();
    }
    if (_searchQuery.isNotEmpty) {
      result = result.where((a) {
        return a.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            a.preview.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            a.tags.any((t) => t.toLowerCase().contains(_searchQuery.toLowerCase()));
      }).toList();
    }
    // Pinned articles first
    result.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      return b.createdAt.compareTo(a.createdAt);
    });
    return result;
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 30) return '${diff.inDays}天前';
    return '${(diff.inDays / 30).floor()}个月前';
  }

  void _showContextMenu(KnowledgeArticle article) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: AppTheme.surfaceCard,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(color: AppTheme.violet.withOpacity(0.3)),
          ),
        ),
        child: SafeArea(
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
              _buildContextMenuItem(
                icon: article.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                label: article.isPinned ? '取消置顶' : '置顶文章',
                onTap: () {
                  setState(() => article.isPinned = !article.isPinned);
                  Navigator.pop(context);
                },
              ),
              _buildContextMenuItem(
                icon: Icons.edit,
                label: '编辑文章',
                onTap: () {
                  Navigator.pop(context);
                  _showCreateEditSheet(article: article);
                },
              ),
              _buildContextMenuItem(
                icon: Icons.share,
                label: '分享文章',
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('链接已复制到剪贴板')),
                  );
                },
              ),
              _buildContextMenuItem(
                icon: Icons.bookmark,
                label: article.isBookmarked ? '取消收藏' : '收藏文章',
                onTap: () {
                  setState(() => article.isBookmarked = !article.isBookmarked);
                  Navigator.pop(context);
                },
              ),
              const Divider(color: AppTheme.border),
              _buildContextMenuItem(
                icon: Icons.delete,
                label: '删除文章',
                iconColor: AppTheme.error,
                textColor: AppTheme.error,
                onTap: () {
                  Navigator.pop(context);
                  _showDeleteConfirm(article);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContextMenuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? iconColor,
    Color? textColor,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor ?? AppTheme.textSecondary),
      title: Text(
        label,
        style: TextStyle(color: textColor ?? AppTheme.textPrimary),
      ),
      onTap: onTap,
    );
  }

  void _showDeleteConfirm(KnowledgeArticle article) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceCard,
        title: const Text(
          '删除文章',
          style: TextStyle(color: AppTheme.error),
        ),
        content: Text(
          '确定要删除《${article.title}》吗？此操作不可撤销。',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              setState(() => _articles.removeWhere((a) => a.id == article.id));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('文章已删除')),
              );
            },
            child: const Text('删除', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasArticles = _articles.isNotEmpty;

    return Scaffold(
      backgroundColor: AppTheme.deepSpace,
      body: CustomScrollView(
        slivers: [
          // Header
          SliverToBoxAdapter(
            child: _buildHeader(),
          ),

          // Search bar
          SliverToBoxAdapter(
            child: _buildSearchBar(),
          ),

          // Categories
          SliverToBoxAdapter(
            child: _buildCategoryChips(),
          ),

          // Action buttons
          SliverToBoxAdapter(
            child: _buildActionButtons(),
          ),

          // Articles list or empty state
          if (hasArticles && _filteredArticles.isNotEmpty)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildArticleCard(_filteredArticles[index]),
                childCount: _filteredArticles.length,
              ),
            ),

          if (hasArticles && _filteredArticles.isEmpty)
            const SliverToBoxAdapter(
              child: _EmptyKnowledgeState(),
            ),

          if (!hasArticles)
            const SliverToBoxAdapter(
              child: _EmptyKnowledgeState(),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
      floatingActionButton: _articles.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () => _showCreateEditSheet(),
              backgroundColor: AppTheme.violet,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                '新建文档',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            )
          : null,
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '团队知识库',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '共享知识，共同成长',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: AppTheme.violetGradient,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.violet.withOpacity(0.3),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Icon(Icons.menu_book, color: Colors.white, size: 24),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _searchQuery = v),
        style: const TextStyle(color: AppTheme.textPrimary),
        decoration: InputDecoration(
          hintText: '搜索文章标题、内容或标签...',
          hintStyle: const TextStyle(color: AppTheme.textTertiary),
          prefixIcon: const Icon(Icons.search, color: AppTheme.textTertiary),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                  icon: const Icon(Icons.clear, size: 18, color: AppTheme.textTertiary),
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildCategoryChips() {
    return Padding(
      padding: const EdgeInsets.only(left: 20, bottom: 16),
      child: SizedBox(
        height: 40,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: _categories.length,
          itemBuilder: (context, index) {
            final category = _categories[index];
            final isActive = _selectedCategory == category;
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: GestureDetector(
                onTap: () => setState(() => _selectedCategory = category),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: isActive ? AppTheme.violetGradient : null,
                    color: isActive ? null : AppTheme.surfaceCard,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isActive ? AppTheme.violet : AppTheme.border,
                    ),
                  ),
                  child: Text(
                    category,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                      color: isActive ? Colors.white : AppTheme.textSecondary,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Row(
        children: [
          Expanded(
            child: GradientButtonWidget(
              label: '新建文档',
              icon: Icons.add,
              onPressed: () => _showCreateEditSheet(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GlassCardWidget(
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('草稿箱功能开发中')),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.drafts, size: 18, color: AppTheme.textSecondary),
                    const SizedBox(width: 8),
                    const Text(
                      '我的草稿',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.error.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$_draftCount',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArticleCard(KnowledgeArticle article) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: GlassCardWidget(
        onTap: () => _showArticleDetail(article),
        onLongPress: () => _showContextMenu(article),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        if (article.isPinned) ...[
                          const Icon(
                            Icons.push_pin,
                            size: 14,
                            color: AppTheme.warning,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            article.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (article.isBookmarked)
                    const Icon(Icons.bookmark, size: 16, color: AppTheme.violet),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                article.preview,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                  height: 1.5,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      gradient: AppTheme.violetGradient,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        article.authorInitials,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    article.author,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.cyan.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      article.category,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.cyan,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  ...article.tags.take(3).map((tag) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceElevated,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Text(
                          tag,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textTertiary,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                  const Spacer(),
                  Icon(Icons.visibility, size: 13, color: AppTheme.textTertiary),
                  const SizedBox(width: 3),
                  Text(
                    '${article.viewCount}',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textTertiary),
                  ),
                  const SizedBox(width: 10),
                  Icon(Icons.favorite, size: 13, color: AppTheme.textTertiary),
                  const SizedBox(width: 3),
                  Text(
                    '${article.likeCount}',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textTertiary),
                  ),
                  const SizedBox(width: 10),
                  Icon(Icons.comment, size: 13, color: AppTheme.textTertiary),
                  const SizedBox(width: 3),
                  Text(
                    '${article.commentCount}',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textTertiary),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatTime(article.createdAt),
                    style: const TextStyle(fontSize: 11, color: AppTheme.textTertiary),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showArticleDetail(KnowledgeArticle article) {
    setState(() => article.viewCount++);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return StatefulBuilder(
            builder: (context, setSheetState) {
              return Container(
                decoration: BoxDecoration(
                  color: AppTheme.deepSpace,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  border: Border(
                    top: BorderSide(color: AppTheme.violet.withOpacity(0.3)),
                  ),
                ),
                child: CustomScrollView(
                  controller: scrollController,
                  slivers: [
                    // Title bar
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 12),
                          Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: AppTheme.border,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    article.title,
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                ),
                                if (article.isPinned)
                                  const Icon(
                                    Icons.push_pin,
                                    size: 20,
                                    color: AppTheme.warning,
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Author info
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    gradient: AppTheme.violetGradient,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      article.authorInitials,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      article.author,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                    Text(
                                      '${_formatTime(article.createdAt)} · ${article.category}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textTertiary,
                                      ),
                                    ),
                                  ],
                                ),
                                const Spacer(),
                                // Action buttons
                                _buildActionIcon(
                                  icon: article.isLiked
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  color: article.isLiked ? AppTheme.error : AppTheme.textSecondary,
                                  count: article.likeCount,
                                  onTap: () {
                                    setSheetState(() {
                                      article.isLiked = !article.isLiked;
                                      article.likeCount += article.isLiked ? 1 : -1;
                                    });
                                    setState(() {});
                                  },
                                ),
                                const SizedBox(width: 16),
                                _buildActionIcon(
                                  icon: article.isBookmarked
                                      ? Icons.bookmark
                                      : Icons.bookmark_border,
                                  color: article.isBookmarked
                                      ? AppTheme.violet
                                      : AppTheme.textSecondary,
                                  onTap: () {
                                    setSheetState(() {
                                      article.isBookmarked = !article.isBookmarked;
                                    });
                                    setState(() {});
                                  },
                                ),
                                const SizedBox(width: 16),
                                _buildActionIcon(
                                  icon: Icons.share,
                                  color: AppTheme.textSecondary,
                                  onTap: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('链接已复制')),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Tags
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Wrap(
                              spacing: 8,
                              children: article.tags.map((tag) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppTheme.surfaceCard,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: AppTheme.border),
                                  ),
                                  child: Text(
                                    tag,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Content
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 20),
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceCard,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppTheme.border),
                            ),
                            child: SelectableText(
                              article.content,
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppTheme.textPrimary,
                                height: 1.8,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          // Comments section
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Row(
                              children: [
                                const Text(
                                  '评论',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.violet.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${article.commentCount}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.violet,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          ..._comments.map((comment) => _buildCommentItem(comment)),
                          const SizedBox(height: 16),
                          // Comment input
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: _buildCommentInput(article, setSheetState),
                          ),
                          const SizedBox(height: 30),
                          // Related articles
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Row(
                              children: [
                                const Text(
                                  '相关文章',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  height: 1,
                                  width: 40,
                                  color: AppTheme.border,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 120,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              children: _articles
                                  .where((a) =>
                                      a.id != article.id &&
                                      a.category == article.category)
                                  .take(3)
                                  .map((a) => _buildRelatedCard(a))
                                  .toList(),
                            ),
                          ),
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildActionIcon({
    required IconData icon,
    required Color color,
    int? count,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: color),
          if (count != null) ...[
            const SizedBox(width: 4),
            Text(
              '$count',
              style: TextStyle(fontSize: 12, color: color),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCommentItem(Comment comment) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: AppTheme.auroraGradient,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                comment.authorInitials,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GlassCardWidget(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          comment.author,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatTime(comment.createdAt),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textTertiary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      comment.content,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentInput(KnowledgeArticle article, StateSetter setSheetState) {
    final TextEditingController controller = TextEditingController();
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
            decoration: const InputDecoration(
              hintText: '写下你的评论...',
              hintStyle: TextStyle(color: AppTheme.textTertiary),
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: () {
            if (controller.text.trim().isEmpty) return;
            setSheetState(() {
              _comments.add(Comment(
                id: 'new_${DateTime.now().millisecondsSinceEpoch}',
                author: '当前用户',
                authorInitials: 'ME',
                content: controller.text,
                createdAt: DateTime.now(),
              ));
              article.commentCount++;
            });
            setState(() {});
          },
          child: Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              gradient: AppTheme.violetGradient,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.send, size: 18, color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _buildRelatedCard(KnowledgeArticle article) {
    return Container(
      width: 220,
      margin: const EdgeInsets.only(right: 10),
      child: GlassCardWidget(
        onTap: () {
          Navigator.pop(context);
          _showArticleDetail(article);
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (article.isPinned)
                const Icon(Icons.push_pin, size: 12, color: AppTheme.warning),
              Text(
                article.title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              Text(
                article.category,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateEditSheet({KnowledgeArticle? article}) {
    final isEdit = article != null;
    final titleController = TextEditingController(text: isEdit ? article.title : '');
    final contentController = TextEditingController(text: isEdit ? article.content : '');
    final tagController = TextEditingController();
    String selectedCategory = isEdit ? article.category : '代码规范';
    bool isDraft = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              top: 20,
              left: 20,
              right: 20,
            ),
            decoration: BoxDecoration(
              color: AppTheme.surfaceCard,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(
                top: BorderSide(color: AppTheme.violet.withOpacity(0.3)),
              ),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppTheme.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    isEdit ? '编辑文章' : '新建文档',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: titleController,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: const InputDecoration(
                      hintText: '文章标题',
                      hintStyle: TextStyle(color: AppTheme.textTertiary),
                      prefixIcon: Icon(Icons.title, color: AppTheme.textTertiary),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '分类',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: _categories
                        .where((c) => c != '全部')
                        .map((category) {
                      final isSelected = selectedCategory == category;
                      return ChoiceChip(
                        label: Text(category),
                        selected: isSelected,
                        onSelected: (_) =>
                            setModalState(() => selectedCategory = category),
                        selectedColor: AppTheme.violet.withOpacity(0.25),
                        backgroundColor: AppTheme.surfaceElevated,
                        labelStyle: TextStyle(
                          color: isSelected ? AppTheme.violet : AppTheme.textSecondary,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                        side: BorderSide(
                          color: isSelected ? AppTheme.violet : AppTheme.border,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: contentController,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    maxLines: 10,
                    decoration: const InputDecoration(
                      hintText: '文章内容（支持 Markdown 格式）...',
                      hintStyle: TextStyle(color: AppTheme.textTertiary),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: tagController,
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: const InputDecoration(
                      hintText: '标签（用逗号分隔）',
                      hintStyle: TextStyle(color: AppTheme.textTertiary),
                      prefixIcon: Icon(Icons.local_offer, color: AppTheme.textTertiary),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text(
                        '保存为草稿',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Switch(
                        value: isDraft,
                        onChanged: (v) => setModalState(() => isDraft = v),
                        activeColor: AppTheme.violet,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.textSecondary,
                            side: const BorderSide(color: AppTheme.border),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('取消'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GradientButtonWidget(
                          label: isDraft ? '保存草稿' : (isEdit ? '更新' : '发布'),
                          icon: isDraft ? Icons.drafts : Icons.publish,
                          onPressed: () {
                            if (titleController.text.trim().isEmpty) return;
                            setState(() {
                              if (isEdit) {
                                final idx = _articles.indexWhere((a) => a.id == article.id);
                                if (idx >= 0) {
                                  _articles[idx] = KnowledgeArticle(
                                    id: article.id,
                                    title: titleController.text,
                                    content: contentController.text,
                                    preview: contentController.text.length > 100
                                        ? contentController.text.substring(0, 100) + '...'
                                        : contentController.text,
                                    author: article.author,
                                    authorInitials: article.authorInitials,
                                    category: selectedCategory,
                                    tags: tagController.text.isEmpty
                                        ? article.tags
                                        : tagController.text.split(',').map((t) => t.trim()).toList(),
                                    viewCount: article.viewCount,
                                    likeCount: article.likeCount,
                                    commentCount: article.commentCount,
                                    createdAt: article.createdAt,
                                    isPinned: article.isPinned,
                                    isBookmarked: article.isBookmarked,
                                    isLiked: article.isLiked,
                                  );
                                }
                              } else {
                                _articles.add(KnowledgeArticle(
                                  id: 'new_${DateTime.now().millisecondsSinceEpoch}',
                                  title: titleController.text,
                                  content: contentController.text,
                                  preview: contentController.text.length > 100
                                      ? contentController.text.substring(0, 100) + '...'
                                      : contentController.text,
                                  author: '当前用户',
                                  authorInitials: 'ME',
                                  category: selectedCategory,
                                  tags: tagController.text.isEmpty
                                      ? []
                                      : tagController.text.split(',').map((t) => t.trim()).toList(),
                                  createdAt: DateTime.now(),
                                ));
                              }
                              if (isDraft) {
                                _draftCount++;
                              }
                            });
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(isDraft ? '草稿已保存' : (isEdit ? '文章已更新' : '文章已发布')),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Empty state widget for knowledge base
class _EmptyKnowledgeState extends StatelessWidget {
  const _EmptyKnowledgeState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.violet.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.menu_book_outlined,
              size: 40,
              color: AppTheme.textTertiary,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            '知识库为空',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '创建第一篇文档，开始积累团队知识',
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          GradientButtonWidget(
            label: '创建文档',
            icon: Icons.add,
            onPressed: () {
              // Would open create sheet
            },
          ),
        ],
      ),
    );
  }
}
