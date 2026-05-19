// lib/screens/memory_manager_screen.dart
// Memory Manager Screen — UI for viewing and managing AI memories.
//
// Organized into sections:
// - Project Memory: Indexed projects with file/function counts
// - Conversation History: Searchable chat history with AI
// - Error Patterns: Common errors and their fixes
// - Frequently Used Snippets: Pinnable code snippets
// - User Corrections: History of user edits to AI code
// - Memory Statistics: Total memory usage and counts
// - Code Preferences: Editable preferences (naming, style, etc.)
//
// Each item supports swipe-to-delete and tap-to-view details.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../services/memory_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Memory Manager Screen
// ═══════════════════════════════════════════════════════════════════════════

/// Memory Manager Screen — Full UI for viewing and managing AI memories.
///
/// Organized into tabbed sections with glassmorphism card design.
/// Top-right actions: Export, Import, Clear All.
class MemoryManagerScreen extends StatefulWidget {
  const MemoryManagerScreen({super.key});

  @override
  State<MemoryManagerScreen> createState() => _MemoryManagerScreenState();
}

class _MemoryManagerScreenState extends State<MemoryManagerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final MemoryService _memory = MemoryService();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 8, vsync: this);
    _initialize();
  }

  Future<void> _initialize() async {
    await _memory.init();
    setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background.withOpacity(0.8),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          '记忆管理',
          style: TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textTertiary,
          indicatorColor: AppTheme.primary,
          indicatorWeight: 2,
          labelStyle: const TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: const TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          tabs: const [
            Tab(text: '项目记忆'),
            Tab(text: '对话历史'),
            Tab(text: '错误模式'),
            Tab(text: '常用片段'),
            Tab(text: '用户修正'),
            Tab(text: 'Rules'),
            Tab(text: '记忆统计'),
            Tab(text: '代码偏好'),
          ],
        ),
        actions: [
          _PopupMenu(memoryService: _memory),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _ProjectMemoryTab(memory: _memory),
                _ConversationHistoryTab(memory: _memory),
                _ErrorPatternsTab(memory: _memory),
                _FrequentSnippetsTab(memory: _memory),
                _UserCorrectionsTab(memory: _memory),
                _MemoryRulesTab(memory: _memory),
                _MemoryStatsTab(memory: _memory),
                _CodePreferencesTab(memory: _memory),
              ],
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Popup Menu (Export / Import / Clear)
// ═══════════════════════════════════════════════════════════════════════════

class _PopupMenu extends StatelessWidget {
  final MemoryService memoryService;

  const _PopupMenu({required this.memoryService});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: AppTheme.textSecondary),
      color: AppTheme.surface,
      onSelected: (value) => _handleMenuAction(context, value),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'export',
          child: Row(
            children: [
              Icon(Icons.download, color: AppTheme.textSecondary, size: 20),
              SizedBox(width: 12),
              Text('导出记忆', style: TextStyle(color: AppTheme.textPrimary)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'import',
          child: Row(
            children: [
              Icon(Icons.upload, color: AppTheme.textSecondary, size: 20),
              SizedBox(width: 12),
              Text('导入记忆', style: TextStyle(color: AppTheme.textPrimary)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'clear',
          child: Row(
            children: [
              Icon(Icons.delete_forever, color: AppTheme.error, size: 20),
              SizedBox(width: 12),
              Text('清除全部', style: TextStyle(color: AppTheme.error)),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _handleMenuAction(BuildContext context, String value) async {
    switch (value) {
      case 'export':
        final json = await memoryService.exportMemories();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('记忆已导出到剪贴板')),
          );
        }
      case 'import':
      // In production, show a dialog to paste JSON.
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('导入功能暂未实现')),
          );
        }
      case 'clear':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppTheme.surface,
            title: const Text('确认清除', style: TextStyle(color: AppTheme.textPrimary)),
            content: const Text(
              '此操作将删除所有记忆数据，不可恢复。确定继续吗？',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消', style: TextStyle(color: AppTheme.textSecondary)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('清除', style: TextStyle(color: AppTheme.error)),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          await memoryService.clearAllMemories();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('所有记忆已清除')),
            );
          }
        }
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Section Header Widget
// ═══════════════════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.primary, size: 18),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Glassmorphism Card
// ═══════════════════════════════════════════════════════════════════════════

class _GlassCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _GlassCard({required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border, width: 1),
          ),
          child: child,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Tab 1: Project Memory
// ═══════════════════════════════════════════════════════════════════════════

class _ProjectMemoryTab extends StatelessWidget {
  final MemoryService memory;

  const _ProjectMemoryTab({required this.memory});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ProjectMemory>>(
      future: memory.getProjectMemories(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
        }
        final projects = snapshot.data!;
        if (projects.isEmpty) {
          return const _EmptyState(message: '暂无项目记忆');
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: projects.length,
          itemBuilder: (context, index) {
            final p = projects[index];
            return Dismissible(
              key: Key(p.id),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                color: AppTheme.error,
                child: const Icon(Icons.delete, color: Colors.white),
              ),
              onDismissed: (_) => memory.deleteProjectMemory(p.id),
              child: _GlassCard(
                onTap: () {},
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.folder, color: AppTheme.primary, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              p.projectName,
                              style: const TextStyle(
                                fontFamily: AppTheme.fontBody,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ),
                          Text(
                            '${p.indexSizeKB.toStringAsFixed(0)} KB',
                            style: const TextStyle(
                              fontFamily: AppTheme.fontBody,
                              fontSize: 12,
                              color: AppTheme.textTertiary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _StatChip(label: '${p.indexedFiles} 文件'),
                          _StatChip(label: '${p.indexedFunctions} 函数'),
                          _StatChip(label: '${p.indexedClasses} 类'),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '最后索引: ${_fmtDate(p.lastIndexed)}',
                        style: const TextStyle(
                          fontFamily: AppTheme.fontBody,
                          fontSize: 11,
                          color: AppTheme.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Tab 2: Conversation History
// ═══════════════════════════════════════════════════════════════════════════

class _ConversationHistoryTab extends StatefulWidget {
  final MemoryService memory;

  const _ConversationHistoryTab({required this.memory});

  @override
  State<_ConversationHistoryTab> createState() => _ConversationHistoryTabState();
}

class _ConversationHistoryTabState extends State<_ConversationHistoryTab> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: '搜索对话...',
              hintStyle: const TextStyle(color: AppTheme.textTertiary, fontSize: 14),
              prefixIcon: const Icon(Icons.search, color: AppTheme.textTertiary, size: 20),
              filled: true,
              fillColor: AppTheme.surfaceInput,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.primary),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<ConversationRecord>>(
            future: _searchQuery.isEmpty
                ? widget.memory.getConversationHistory()
                : widget.memory.searchConversations(_searchQuery),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
              }
              final conversations = snapshot.data!;
              if (conversations.isEmpty) {
                return const _EmptyState(message: '暂无对话记录');
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: conversations.length,
                itemBuilder: (context, index) {
                  final c = conversations[index];
                  return Dismissible(
                    key: Key(c.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      color: AppTheme.error,
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    onDismissed: (_) => widget.memory.deleteConversation(c.id),
                    child: _GlassCard(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  c.isPinned ? Icons.push_pin : Icons.chat_bubble_outline,
                                  color: c.isPinned ? AppTheme.accent : AppTheme.textTertiary,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    c.userMessage.length > 50
                                        ? '${c.userMessage.substring(0, 50)}...'
                                        : c.userMessage,
                                    style: const TextStyle(
                                      fontFamily: AppTheme.fontBody,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              c.aiResponse.length > 100
                                  ? '${c.aiResponse.substring(0, 100)}...'
                                  : c.aiResponse,
                              style: const TextStyle(
                                fontFamily: AppTheme.fontBody,
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Text(
                                  _fmtDate(c.timestamp),
                                  style: const TextStyle(
                                    fontFamily: AppTheme.fontBody,
                                    fontSize: 11,
                                    color: AppTheme.textTertiary,
                                  ),
                                ),
                                if (c.projectId != null) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryMuted,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      c.projectId!,
                                      style: const TextStyle(
                                        fontFamily: AppTheme.fontBody,
                                        fontSize: 10,
                                        color: AppTheme.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Tab 3: Error Patterns
// ═══════════════════════════════════════════════════════════════════════════

class _ErrorPatternsTab extends StatelessWidget {
  final MemoryService memory;

  const _ErrorPatternsTab({required this.memory});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ErrorPattern>>(
      future: memory.getErrorPatterns(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
        }
        final errors = snapshot.data!;
        if (errors.isEmpty) {
          return const _EmptyState(message: '暂无错误模式记录');
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: errors.length,
          itemBuilder: (context, index) {
            final e = errors[index];
            return Dismissible(
              key: Key(e.id),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                color: AppTheme.error,
                child: const Icon(Icons.delete, color: Colors.white),
              ),
              onDismissed: (_) => memory.deleteErrorPattern(e.id),
              child: _GlassCard(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.bug_report, color: AppTheme.error, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              e.errorType,
                              style: const TextStyle(
                                fontFamily: AppTheme.fontBody,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.error.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${e.occurrenceCount} 次',
                              style: const TextStyle(
                                fontFamily: AppTheme.fontBody,
                                fontSize: 11,
                                color: AppTheme.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        e.errorMessage,
                        style: const TextStyle(
                          fontFamily: AppTheme.fontBody,
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.success.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          e.solution,
                          style: const TextStyle(
                            fontFamily: AppTheme.fontBody,
                            fontSize: 12,
                            color: AppTheme.success,
                          ),
                        ),
                      ),
                      if (e.relatedFile != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '相关文件: ${e.relatedFile}',
                            style: const TextStyle(
                              fontFamily: AppTheme.fontBody,
                              fontSize: 11,
                              color: AppTheme.textTertiary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Tab 4: Frequent Snippets
// ═══════════════════════════════════════════════════════════════════════════

class _FrequentSnippetsTab extends StatelessWidget {
  final MemoryService memory;

  const _FrequentSnippetsTab({required this.memory});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<FrequentSnippet>>(
      future: memory.getFrequentSnippets(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
        }
        final snippets = snapshot.data!;
        if (snippets.isEmpty) {
          return const _EmptyState(message: '暂无常用代码片段');
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: snippets.length,
          itemBuilder: (context, index) {
            final s = snippets[index];
            return _GlassCard(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          s.isPinned ? Icons.push_pin : Icons.code,
                          color: s.isPinned ? AppTheme.accent : AppTheme.primary,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryMuted,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            s.language,
                            style: const TextStyle(
                              fontFamily: AppTheme.fontBody,
                              fontSize: 11,
                              color: AppTheme.primary,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${s.usageCount} 次使用',
                          style: const TextStyle(
                            fontFamily: AppTheme.fontBody,
                            fontSize: 11,
                            color: AppTheme.textTertiary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () => memory.pinSnippet(s.id),
                          child: Icon(
                            s.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                            color: s.isPinned ? AppTheme.accent : AppTheme.textTertiary,
                            size: 18,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.editorBackground,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        s.code.length > 200 ? '${s.code.substring(0, 200)}...' : s.code,
                        style: const TextStyle(
                          fontFamily: AppTheme.fontCode,
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Tab 5: User Corrections
// ═══════════════════════════════════════════════════════════════════════════

class _UserCorrectionsTab extends StatelessWidget {
  final MemoryService memory;

  const _UserCorrectionsTab({required this.memory});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<UserCorrection>>(
      future: memory.getUserCorrections(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
        }
        final corrections = snapshot.data!;
        if (corrections.isEmpty) {
          return const _EmptyState(message: '暂无用户修正记录');
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: corrections.length,
          itemBuilder: (context, index) {
            final c = corrections[index];
            return Dismissible(
              key: Key(c.id),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                color: AppTheme.error,
                child: const Icon(Icons.delete, color: Colors.white),
              ),
              onDismissed: (_) => memory.deleteCorrection(c.id),
              child: _GlassCard(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.edit_note, color: AppTheme.warning, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              c.reason,
                              style: const TextStyle(
                                fontFamily: AppTheme.fontBody,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'AI 代码:',
                        style: TextStyle(
                          fontFamily: AppTheme.fontBody,
                          fontSize: 11,
                          color: AppTheme.textTertiary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _CodeBlock(code: c.originalCode),
                      const SizedBox(height: 8),
                      const Text(
                        '修正后:',
                        style: TextStyle(
                          fontFamily: AppTheme.fontBody,
                          fontSize: 11,
                          color: AppTheme.success,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _CodeBlock(code: c.correctedCode),
                      const SizedBox(height: 6),
                      Text(
                        _fmtDate(c.timestamp),
                        style: const TextStyle(
                          fontFamily: AppTheme.fontBody,
                          fontSize: 11,
                          color: AppTheme.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Tab 6: Memory Rules
// ═══════════════════════════════════════════════════════════════════════════

class _MemoryRulesTab extends StatefulWidget {
  final MemoryService memory;

  const _MemoryRulesTab({required this.memory});

  @override
  State<_MemoryRulesTab> createState() => _MemoryRulesTabState();
}

class _MemoryRulesTabState extends State<_MemoryRulesTab> {
  late Future<List<MemoryRule>> _rules;
  final TextEditingController _ruleTitleController = TextEditingController();
  final TextEditingController _ruleBodyController = TextEditingController();
  final TextEditingController _ruleCategoryController = TextEditingController(text: 'user-rule');

  @override
  void initState() {
    super.initState();
    _rules = widget.memory.getMemoryRules();
  }

  @override
  void dispose() {
    _ruleTitleController.dispose();
    _ruleBodyController.dispose();
    _ruleCategoryController.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _rules = widget.memory.getMemoryRules();
    });
  }

  Future<void> _copyRulesFile() async {
    final markdown = await widget.memory.buildRulesMarkdown();
    await Clipboard.setData(ClipboardData(text: markdown));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('MOBILECODE_RULES.md 内容已复制'),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showAddRuleDialog() async {
    _ruleTitleController.clear();
    _ruleBodyController.clear();
    _ruleCategoryController.text = 'user-rule';

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        surfaceTintColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.border),
        ),
        title: const Text(
          '新增 Rule',
          style: TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _RuleInputField(
                controller: _ruleTitleController,
                label: '标题',
                hint: '例如：HTML 默认走 GitHub Pages 发布',
              ),
              const SizedBox(height: 10),
              _RuleInputField(
                controller: _ruleCategoryController,
                label: '分类',
                hint: 'user-rule / repo-insight / workflow',
              ),
              const SizedBox(height: 10),
              _RuleInputField(
                controller: _ruleBodyController,
                label: '规则内容',
                hint: '写成短句，明确 MobileCode 以后应该如何执行。',
                maxLines: 4,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              final title = _ruleTitleController.text.trim();
              final body = _ruleBodyController.text.trim();
              if (title.isEmpty || body.isEmpty) return;
              await widget.memory.upsertMemoryRule(
                MemoryRule(
                  id: 'manual_rule_${DateTime.now().microsecondsSinceEpoch}',
                  title: title,
                  category: _ruleCategoryController.text.trim().isEmpty
                      ? 'user-rule'
                      : _ruleCategoryController.text.trim(),
                  rule: body,
                  source: 'manual',
                  evidenceRepos: const [],
                  createdAt: DateTime.now(),
                  enabled: true,
                ),
              );
              if (context.mounted) Navigator.of(context).pop();
              _reload();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: AppTheme.textOnPrimary,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
            ),
            icon: const Icon(Icons.save_outlined, size: 16),
            label: const Text('保存'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MemoryRule>>(
      future: _rules,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
        }
        final rules = snapshot.data!;
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: rules.isEmpty ? 2 : rules.length + 1,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            if (index == 0) {
              return _RulesFileCard(
                activeRuleCount: rules.where((rule) => rule.enabled).length,
                onAddRule: _showAddRuleDialog,
                onCopyRulesFile: _copyRulesFile,
              );
            }
            if (rules.isEmpty) {
              return const _RulesEmptyCard();
            }
            final ruleIndex = index - 1;
            if (ruleIndex >= rules.length) {
              return const SizedBox.shrink();
            }
            final rule = rules[ruleIndex];
            return _GlassCard(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.psychology_alt_outlined, color: AppTheme.accent, size: 19),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                rule.title,
                                style: const TextStyle(
                                  fontFamily: AppTheme.fontBody,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${rule.category} · ${rule.source}',
                                style: const TextStyle(
                                  fontFamily: AppTheme.fontBody,
                                  fontSize: 12,
                                  color: AppTheme.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: '删除规则',
                          onPressed: () async {
                            await widget.memory.removeMemoryRule(rule.id);
                            _reload();
                          },
                          icon: const Icon(Icons.delete_outline, color: AppTheme.error, size: 20),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      rule.rule,
                      style: const TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                        height: 1.35,
                      ),
                    ),
                    if (rule.evidenceRepos.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final repo in rule.evidenceRepos.take(4))
                            _StatChip(label: repo),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _RulesFileCard extends StatelessWidget {
  const _RulesFileCard({
    required this.activeRuleCount,
    required this.onAddRule,
    required this.onCopyRulesFile,
  });

  final int activeRuleCount;
  final VoidCallback onAddRule;
  final VoidCallback onCopyRulesFile;

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
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
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(Icons.rule_outlined, color: AppTheme.primary, size: 20),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MOBILECODE_RULES.md',
                        style: TextStyle(
                          fontFamily: AppTheme.fontBody,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Rules 是用户批准后的行为准则；Memory 是证据、偏好和可提案的经验。',
                        style: TextStyle(
                          fontFamily: AppTheme.fontBody,
                          fontSize: 12,
                          height: 1.35,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatChip(label: '$activeRuleCount active rules'),
                const _StatChip(label: 'user approved'),
                const _StatChip(label: 'prompt injected later'),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onAddRule,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('新增 Rule'),
                ),
                OutlinedButton.icon(
                  onPressed: onCopyRulesFile,
                  icon: const Icon(Icons.copy_all_outlined, size: 16),
                  label: const Text('复制 RULES.md'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RulesEmptyCard extends StatelessWidget {
  const _RulesEmptyCard();

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: const Padding(
        padding: EdgeInsets.all(18),
        child: Column(
          children: [
            Icon(Icons.rule_outlined, color: AppTheme.textTertiary, size: 34),
            SizedBox(height: 10),
            Text(
              '还没有批准的 Rules',
              style: TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            SizedBox(height: 6),
            Text(
              '你可以手动新增，也可以从仓库分析、Role/Memory proposal 中接受规则。Memory 不会自动变成 Rule。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 12,
                height: 1.35,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RuleInputField extends StatelessWidget {
  const _RuleInputField({
    required this.controller,
    required this.label,
    required this.hint,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(
        fontFamily: AppTheme.fontBody,
        fontSize: 14,
        color: AppTheme.textPrimary,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: AppTheme.textSecondary),
        hintStyle: const TextStyle(color: AppTheme.textTertiary, fontSize: 12),
        filled: true,
        fillColor: AppTheme.surfaceInput,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Tab 7: Memory Statistics
// ═══════════════════════════════════════════════════════════════════════════

class _MemoryStatsTab extends StatelessWidget {
  final MemoryService memory;

  const _MemoryStatsTab({required this.memory});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MemoryStats>(
      future: memory.getMemoryStats(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
        }
        final stats = snapshot.data!;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _StatCard(
                title: '总项目数',
                value: '${stats.totalProjects}',
                icon: Icons.folder,
                color: AppTheme.primary,
              ),
              _StatCard(
                title: '对话记录',
                value: '${stats.totalConversations}',
                icon: Icons.chat,
                color: AppTheme.accent,
              ),
              _StatCard(
                title: '错误模式',
                value: '${stats.totalErrorPatterns}',
                icon: Icons.bug_report,
                color: AppTheme.error,
              ),
              _StatCard(
                title: '代码片段',
                value: '${stats.totalSnippets}',
                icon: Icons.code,
                color: AppTheme.warning,
              ),
              _StatCard(
                title: '规则洞察',
                value: '${stats.totalRules}',
                icon: Icons.psychology_alt,
                color: AppTheme.accent,
              ),
              const SizedBox(height: 16),
              _GlassCard(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Text(
                        '存储概览',
                        style: TextStyle(
                          fontFamily: AppTheme.fontBody,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _MemoryBar(label: '项目', value: stats.totalProjects, max: stats.totalItems, color: AppTheme.primary),
                      _MemoryBar(label: '对话', value: stats.totalConversations, max: stats.totalItems, color: AppTheme.accent),
                      _MemoryBar(label: '错误', value: stats.totalErrorPatterns, max: stats.totalItems, color: AppTheme.error),
                      _MemoryBar(label: '片段', value: stats.totalSnippets, max: stats.totalItems, color: AppTheme.warning),
                      _MemoryBar(label: '规则', value: stats.totalRules, max: stats.totalItems, color: AppTheme.accent),
                      const SizedBox(height: 12),
                      Text(
                        '总占用: ${stats.memorySizeKB} KB',
                        style: const TextStyle(
                          fontFamily: AppTheme.fontBody,
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Tab 7: Code Preferences
// ═══════════════════════════════════════════════════════════════════════════

class _CodePreferencesTab extends StatefulWidget {
  final MemoryService memory;

  const _CodePreferencesTab({required this.memory});

  @override
  State<_CodePreferencesTab> createState() => _CodePreferencesTabState();
}

class _CodePreferencesTabState extends State<_CodePreferencesTab> {
  CodePreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final p = await widget.memory.getCodePreferences();
    setState(() => _prefs = p);
  }

  @override
  Widget build(BuildContext context) {
    if (_prefs == null) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }
    final p = _prefs!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('命名规范'),
          _buildDropdown<NamingConvention>(
            value: p.namingConvention,
            items: NamingConvention.values,
            labels: NamingConvention.values.map((v) => v.displayName).toList(),
            onChanged: (v) {
              if (v != null) {
                setState(() => p.namingConvention = v);
                widget.memory.updateCodePreferences(p);
              }
            },
          ),
          _buildSectionTitle('缩进风格'),
          Row(
            children: [
              Expanded(
                child: _buildDropdown<IndentStyle>(
                  value: p.indentStyle,
                  items: IndentStyle.values,
                  labels: IndentStyle.values.map((v) => v.label).toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => p.indentStyle = v);
                      widget.memory.updateCodePreferences(p);
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDropdown<int>(
                  value: p.indentSize,
                  items: const [2, 4],
                  labels: const ['2 空格', '4 空格'],
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => p.indentSize = v);
                      widget.memory.updateCodePreferences(p);
                    }
                  },
                ),
              ),
            ],
          ),
          _buildSectionTitle('引号风格'),
          _buildDropdown<QuoteStyle>(
            value: p.quoteStyle,
            items: QuoteStyle.values,
            labels: QuoteStyle.values.map((v) => v.label).toList(),
            onChanged: (v) {
              if (v != null) {
                setState(() => p.quoteStyle = v);
                widget.memory.updateCodePreferences(p);
              }
            },
          ),
          _buildSectionTitle('注释风格'),
          _buildDropdown<CommentStyle>(
            value: p.commentStyle,
            items: CommentStyle.values,
            labels: CommentStyle.values.map((v) => v.displayName).toList(),
            onChanged: (v) {
              if (v != null) {
                setState(() => p.commentStyle = v);
                widget.memory.updateCodePreferences(p);
              }
            },
          ),
          _buildSectionTitle('其他选项'),
          _buildSwitchTile('使用尾随逗号', p.useTrailingCommas, (v) {
            setState(() => p.useTrailingCommas = v);
            widget.memory.updateCodePreferences(p);
          }),
          _buildSwitchTile('优先使用 const', p.preferConst, (v) {
            setState(() => p.preferConst = v);
            widget.memory.updateCodePreferences(p);
          }),
          _buildSwitchTile('优先使用 final', p.preferFinal, (v) {
            setState(() => p.preferFinal = v);
            widget.memory.updateCodePreferences(p);
          }),
          _buildSectionTitle('最大行长度'),
          Slider(
            value: p.maxLineLength.toDouble(),
            min: 60,
            max: 160,
            divisions: 10,
            label: '${p.maxLineLength}',
            activeColor: AppTheme.primary,
            inactiveColor: AppTheme.border,
            onChanged: (v) {
              setState(() => p.maxLineLength = v.round());
            },
            onChangeEnd: (v) {
              widget.memory.updateCodePreferences(p);
            },
          ),
          Center(
            child: Text(
              '${p.maxLineLength} 字符',
              style: const TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: TextButton.icon(
              onPressed: () async {
                await widget.memory.resetCodePreferences();
                await _loadPrefs();
              },
              icon: const Icon(Icons.refresh, color: AppTheme.error, size: 18),
              label: const Text(
                '恢复默认',
                style: TextStyle(color: AppTheme.error),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: AppTheme.fontBody,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }

  Widget _buildDropdown<T>({
    required T value,
    required List<T> items,
    required List<String> labels,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceInput,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: AppTheme.surface,
          style: const TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 14,
            color: AppTheme.textPrimary,
          ),
          icon: const Icon(Icons.arrow_drop_down, color: AppTheme.textTertiary),
          items: List.generate(items.length, (i) {
            return DropdownMenuItem(
              value: items[i],
              child: Text(labels[i]),
            );
          }),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildSwitchTile(String title, bool value, ValueChanged<bool> onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: SwitchListTile(
        title: Text(
          title,
          style: const TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 14,
            color: AppTheme.textPrimary,
          ),
        ),
        value: value,
        activeColor: AppTheme.primary,
        onChanged: onChanged,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Shared Widgets
// ═══════════════════════════════════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  final String message;

  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.storage_outlined,
            size: 48,
            color: AppTheme.textTertiary.withOpacity(0.5),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 14,
              color: AppTheme.textTertiary.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;

  const _StatChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.primaryMuted,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: AppTheme.fontBody,
          fontSize: 11,
          color: AppTheme.primary,
        ),
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  final String code;

  const _CodeBlock({required this.code});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.editorBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Text(
        code.length > 150 ? '${code.substring(0, 150)}...' : code,
        style: const TextStyle(
          fontFamily: AppTheme.fontCode,
          fontSize: 11,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _GlassCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontBody,
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemoryBar extends StatelessWidget {
  final String label;
  final int value;
  final int max;
  final Color color;

  const _MemoryBar({
    required this.label,
    required this.value,
    required this.max,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final pct = max > 0 ? value / max : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                backgroundColor: AppTheme.border,
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 8,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 30,
            child: Text(
              '$value',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _fmtDate(DateTime dt) {
  return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}
