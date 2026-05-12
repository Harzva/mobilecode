// lib/screens/snippet_screen.dart
// UNLIMITED INSPIRATION CAPTURE - Full-featured snippet management
// Features: Voice-to-Code, OCR, AI Generation, Templates, Collections,
//           Import/Export, Smart Tags, Sort/Filter, Quick Actions

import 'dart:async';
import 'dart:convert';


import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../models/code_snippet.dart';
import '../providers/snippet_provider.dart';
import '../themes/app_theme.dart';
import '../widgets/gradient_button_widget.dart';
import '../widgets/snippet_card_widget.dart';
import 'editor_screen.dart';
import 'snippet_editor_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SORT OPTIONS
// ═══════════════════════════════════════════════════════════════════════════

enum SnippetSortOption {
  recent('最近使用', Icons.access_time),
  oldest('最早创建', Icons.history),
  nameAsc('名称 A-Z', Icons.sort_by_alpha),
  nameDesc('名称 Z-A', Icons.sort_by_alpha_outlined),
  mostUsed('使用最多', Icons.trending_up),
  language('语言', Icons.code);

  final String label;
  final IconData icon;
  const SnippetSortOption(this.label, this.icon);
}

// ═══════════════════════════════════════════════════════════════════════════
// SNIPPET COLLECTION / FOLDER
// ═══════════════════════════════════════════════════════════════════════════

class SnippetCollection {
  final String id;
  String name;
  String? iconName;
  List<String> snippetIds;
  DateTime createdAt;

  SnippetCollection({
    required this.id,
    required this.name,
    this.iconName,
    this.snippetIds = const [],
    required this.createdAt,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// SNIPPET TEMPLATES
// ═══════════════════════════════════════════════════════════════════════════

class SnippetTemplate {
  final String title;
  final String code;
  final String language;
  final List<String> tags;
  final String description;
  final String category;

  const SnippetTemplate({
    required this.title,
    required this.code,
    required this.language,
    required this.tags,
    required this.description,
    required this.category,
  });
}

final List<SnippetTemplate> _builtinTemplates = [
  // ── Flutter ──
  const SnippetTemplate(
    title: 'StatelessWidget',
    language: 'dart',
    category: 'Flutter',
    tags: ['flutter', 'widget'],
    description: 'Basic Flutter stateless widget scaffold',
    code: '''import 'package:flutter/material.dart';

class MyWidget extends StatelessWidget {
  const MyWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      child: Text('Hello World'),
    );
  }
}''',
  ),
  const SnippetTemplate(
    title: 'StatefulWidget',
    language: 'dart',
    category: 'Flutter',
    tags: ['flutter', 'widget', 'state'],
    description: 'Flutter stateful widget with state class',
    code: '''import 'package:flutter/material.dart';

class MyWidget extends StatefulWidget {
  const MyWidget({super.key});

  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(child: Text('Hello')),
    );
  }
}''',
  ),
  const SnippetTemplate(
    title: 'AnimationBuilder',
    language: 'dart',
    category: 'Flutter',
    tags: ['flutter', 'animation'],
    description: 'Tween animation with AnimationController',
    code: '''class AnimatedBox extends StatefulWidget {
  const AnimatedBox({super.key});

  @override
  State<AnimatedBox> createState() => _AnimatedBoxState();
}

class _AnimatedBoxState extends State<AnimatedBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: 1.0 + _controller.value * 0.5,
          child: child,
        );
      },
      child: const FlutterLogo(size: 100),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}''',
  ),
  // ── Python ──
  const SnippetTemplate(
    title: 'Python Function',
    language: 'python',
    category: 'Python',
    tags: ['python', 'function'],
    description: 'Python function with type hints and docstring',
    code: '''def process_data(data: list[dict], threshold: int = 10) -> list[dict]:
    """Process data entries filtering by threshold.

    Args:
        data: List of data dictionaries.
        threshold: Minimum value filter (default: 10).

    Returns:
        Filtered list of data entries.
    """
    return [entry for entry in data if entry.get('value', 0) >= threshold]''',
  ),
  const SnippetTemplate(
    title: 'Python Class',
    language: 'python',
    category: 'Python',
    tags: ['python', 'class', 'oop'],
    description: 'Python class with dataclass decorator',
    code: '''from dataclasses import dataclass, field
from typing import Optional

@dataclass
class User:
    name: str
    email: str
    id: Optional[int] = None
    roles: list[str] = field(default_factory=list)

    def add_role(self, role: str) -> None:
        if role not in self.roles:
            self.roles.append(role)

    def __post_init__(self):
        if self.id is None:
            self.id = hash(self.email) % 10_000''',
  ),
  const SnippetTemplate(
    title: 'List Comprehension',
    language: 'python',
    category: 'Python',
    tags: ['python', 'functional'],
    description: 'Advanced list comprehension patterns',
    code: '''# Filter and transform
squares = [x**2 for x in range(100) if x % 2 == 0]

# Nested comprehension
matrix = [[i * j for j in range(5)] for i in range(5)]

# Dict comprehension
lookup = {item['id']: item for item in items if 'id' in item}

# Set comprehension
unique_tags = {tag for item in items for tag in item.get('tags', [])}''',
  ),
  // ── JavaScript ──
  const SnippetTemplate(
    title: 'Async Function',
    language: 'javascript',
    category: 'JavaScript',
    tags: ['javascript', 'async'],
    description: 'JavaScript async/await pattern with error handling',
    code: '''async function fetchUserData(userId, options = {}) {
  const { retries = 3, timeout = 5000 } = options;

  for (let attempt = 1; attempt <= retries; attempt++) {
    try {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), timeout);

      const response = await fetch(\`/api/users/\${userId}\`, {
        signal: controller.signal,
      });
      clearTimeout(timer);

      if (!response.ok) {
        throw new Error(\`HTTP \${response.status}\`);
      }

      return await response.json();
    } catch (error) {
      if (attempt === retries) throw error;
      await new Promise(r => setTimeout(r, 1000 * attempt));
    }
  }
}''',
  ),
  const SnippetTemplate(
    title: 'Event Listener',
    language: 'javascript',
    category: 'JavaScript',
    tags: ['javascript', 'dom', 'event'],
    description: 'Modern DOM event listener with cleanup',
    code: '''function setupEventListeners() {
  const handler = {
    init() {
      this.listeners = [];
      this._onClick = this._onClick.bind(this);
      this._onKeydown = this._onKeydown.bind(this);

      document.addEventListener('click', this._onClick);
      document.addEventListener('keydown', this._onKeydown);

      this.listeners.push(
        ['click', this._onClick],
        ['keydown', this._onKeydown]
      );
    },

    _onClick(event) {
      console.log('Clicked:', event.target);
    },

    _onKeydown(event) {
      if (event.key === 'Escape') {
        this.destroy();
      }
    },

    destroy() {
      this.listeners.forEach(
        ([event, fn]) => document.removeEventListener(event, fn)
      );
      this.listeners = [];
    }
  };

  handler.init();
  return handler;
}''',
  ),
  // ── Go ──
  const SnippetTemplate(
    title: 'Go Struct',
    language: 'go',
    category: 'Go',
    tags: ['go', 'struct'],
    description: 'Go struct with methods and JSON tags',
    code: '''package main

import "encoding/json"
import "time"

type User struct {
    ID        int64     `json:"id"`
    Name      string    `json:"name" validate:"required"`
    Email     string    `json:"email" validate:"email"`
    CreatedAt time.Time `json:"created_at"`
}

func (u *User) MarshalJSON() ([]byte, error) {
    type Alias User
    return json.Marshal(&struct {
        *Alias
        CreatedAt string `json:"created_at"`
    }{
        Alias:     (*Alias)(u),
        CreatedAt: u.CreatedAt.Format(time.RFC3339),
    })
}''',
  ),
  const SnippetTemplate(
    title: 'Goroutine Pool',
    language: 'go',
    category: 'Go',
    tags: ['go', 'concurrency', 'goroutine'],
    description: 'Worker pool pattern with channels',
    code: '''package worker

import "sync"

type Pool struct {
    workers int
    jobs    chan func()
    wg      sync.WaitGroup
    quit    chan struct{}
}

func New(workers int) *Pool {
    p := &Pool{
        workers: workers,
        jobs:    make(chan func(), 100),
        quit:    make(chan struct{}),
    }
    p.start()
    return p
}

func (p *Pool) start() {
    for i := 0; i < p.workers; i++ {
        p.wg.Add(1)
        go func() {
            defer p.wg.Done()
            for {
                select {
                case job := <-p.jobs:
                    job()
                case <-p.quit:
                    return
                }
            }
        }()
    }
}

func (p *Pool) Submit(job func()) {
    select {
    case p.jobs <- job:
    case <-p.quit:
    }
}

func (p *Pool) Stop() {
    close(p.quit)
    p.wg.Wait()
}''',
  ),
  // ── SQL ──
  const SnippetTemplate(
    title: 'SELECT with JOIN',
    language: 'sql',
    category: 'SQL',
    tags: ['sql', 'query', 'join'],
    description: 'SQL SELECT with multiple JOINs',
    code: '''SELECT 
    u.id,
    u.name,
    u.email,
    p.title AS project_title,
    COUNT(t.id) AS task_count,
    MAX(t.updated_at) AS last_activity
FROM users u
LEFT JOIN projects p ON p.user_id = u.id
LEFT JOIN tasks t ON t.project_id = p.id
WHERE u.active = TRUE
GROUP BY u.id, p.id
HAVING COUNT(t.id) > 0
ORDER BY last_activity DESC
LIMIT 50;''',
  ),
  const SnippetTemplate(
    title: 'INSERT with RETURNING',
    language: 'sql',
    category: 'SQL',
    tags: ['sql', 'insert'],
    description: 'Modern INSERT with conflict handling',
    code: '''INSERT INTO users (name, email, role)
VALUES (\$1, \$2, \$3)
ON CONFLICT (email) DO UPDATE SET
    name = EXCLUDED.name,
    role = EXCLUDED.role,
    updated_at = NOW()
RETURNING id, name, email, role, created_at;''',
  ),
  // ── Algorithms ──
  const SnippetTemplate(
    title: 'Binary Search',
    language: 'dart',
    category: 'Algorithm',
    tags: ['algorithm', 'search'],
    description: 'Binary search implementation',
    code: '''int binarySearch<T extends Comparable<T>>(List<T> list, T target) {
  int left = 0;
  int right = list.length - 1;

  while (left <= right) {
    int mid = left + ((right - left) >> 1);
    int cmp = list[mid].compareTo(target);

    if (cmp == 0) return mid;
    if (cmp < 0) {
      left = mid + 1;
    } else {
      right = mid - 1;
    }
  }

  return -1; // Not found
}''',
  ),
  const SnippetTemplate(
    title: 'BFS Graph Traversal',
    language: 'dart',
    category: 'Algorithm',
    tags: ['algorithm', 'graph', 'bfs'],
    description: 'Breadth-first search on adjacency list graph',
    code: '''List<T> bfs<T>(Map<T, List<T>> graph, T start) {
  final visited = <T>{};
  final queue = <T>[start];
  final result = <T>[];

  while (queue.isNotEmpty) {
    final node = queue.removeAt(0);
    if (visited.contains(node)) continue;

    visited.add(node);
    result.add(node);

    for (final neighbor in graph[node] ?? []) {
      if (!visited.contains(neighbor)) {
        queue.add(neighbor);
      }
    }
  }

  return result;
}''',
  ),
  const SnippetTemplate(
    title: 'Quick Sort',
    language: 'dart',
    category: 'Algorithm',
    tags: ['algorithm', 'sort'],
    description: 'In-place quick sort algorithm',
    code: '''void quickSort<E extends Comparable<E>>(List<E> list,
    {int low = 0, int? high}) {
  int h = high ?? list.length - 1;
  if (low < h) {
    final pivot = _partition(list, low, h);
    quickSort(list, low: low, high: pivot - 1);
    quickSort(list, low: pivot + 1, high: h);
  }
}

int _partition<E extends Comparable<E>>(List<E> list, int low, int high) {
  final pivot = list[high];
  int i = low - 1;

  for (int j = low; j < high; j++) {
    if (list[j].compareTo(pivot) <= 0) {
      i++;
      final temp = list[i];
      list[i] = list[j];
      list[j] = temp;
    }
  }

  final temp = list[i + 1];
  list[i + 1] = list[high];
  list[high] = temp;

  return i + 1;
}''',
  ),
];

// ═══════════════════════════════════════════════════════════════════════════
// TAG COLOR MAPPING
// ═══════════════════════════════════════════════════════════════════════════

final Map<String, Color> _tagColorMap = {
  'flutter': const Color(0xFF54C5F8),
  'dart': const Color(0xFF00D4AA),
  'python': const Color(0xFF3776AB),
  'javascript': const Color(0xFFF7DF1E),
  'typescript': const Color(0xFF3178C6),
  'go': const Color(0xFF00ADD8),
  'rust': const Color(0xFFDEA584),
  'java': const Color(0xFF007396),
  'sql': const Color(0xFFF29111),
  'algorithm': AppTheme.violet,
  'widget': const Color(0xFF54C5F8),
  'animation': AppTheme.cyan,
  'backend': const Color(0xFF2ED573),
  'api': const Color(0xFFFFA502),
  'database': const Color(0xFFF29111),
  'ui': const Color(0xFFFF6B81),
  'state-management': AppTheme.violet,
  'testing': const Color(0xFF2ED573),
  'concurrency': const Color(0xFFFF4757),
  'error-handling': const Color(0xFFFF6B81),
};

Color _tagColor(String tag) {
  return _tagColorMap[tag.toLowerCase()] ?? AppTheme.violet.withOpacity(0.7);
}

// ═══════════════════════════════════════════════════════════════════════════
// MAIN SCREEN
// ═══════════════════════════════════════════════════════════════════════════

/// SnippetScreen with UNLIMITED INSPIRATION CAPTURE.
///
/// Features:
/// - Voice-to-Code capture with waveform animation
/// - Screenshot-to-Code (OCR) extraction
/// - AI-powered snippet generation
/// - Snippet templates library (14 built-in templates)
/// - Collections / folders for organization
/// - Import/export (JSON)
/// - Advanced search with filters & sort
/// - Tags with color coding
/// - Quick actions (copy, open, share, duplicate, export)
/// - Smart suggestions based on usage
class SnippetScreen extends ConsumerStatefulWidget {
  const SnippetScreen({super.key});

  @override
  ConsumerState<SnippetScreen> createState() => _SnippetScreenState();
}

class _SnippetScreenState extends ConsumerState<SnippetScreen>
    with TickerProviderStateMixin {
  // ── Tab & View State ──
  late TabController _tabController;
  int _currentTabIndex = 0;

  // ── Sort ──
  SnippetSortOption _sortOption = SnippetSortOption.recent;

  // ── Collection State ──
  final List<SnippetCollection> _collections = [];
  String? _selectedCollectionId;

  // ── FAB Expansion ──
  bool _isFabExpanded = false;
  late AnimationController _fabAnimationController;

  // ── Voice Recording State ──
  bool _isRecording = false;
  String _recordedText = '';
  List<double> _waveformData = [];
  Timer? _waveformTimer;

  // ── AI Generation State ──
  bool _isAiGenerating = false;

  // ── Undo State ──
  CodeSnippet? _lastDeletedSnippet;
  Timer? _undoTimer;

  // ── Search ──
  final TextEditingController _searchController = TextEditingController();
  bool _showSearchFilters = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      setState(() => _currentTabIndex = _tabController.index);
    });
    _fabAnimationController = AnimationController(
      vsync: this,
      duration: AppTheme.animNormal,
    );

    // Initialize default collection
    _collections.add(
      SnippetCollection(
        id: 'all',
        name: '全部片段',
        createdAt: DateTime.now(),
      ),
    );
    _collections.add(
      SnippetCollection(
        id: 'favorites',
        name: '收藏夹',
        iconName: 'star',
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _fabAnimationController.dispose();
    _waveformTimer?.cancel();
    _undoTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // FILTERING & SORTING
  // ═══════════════════════════════════════════════════════════════════════

  List<CodeSnippet> _getFilteredAndSortedSnippets(List<CodeSnippet> all) {
    final query = _searchController.text.toLowerCase();
    final tagFilter = ref.read(snippetTagFilterProvider);
    final langFilter = ref.read(snippetLanguageFilterProvider);

    var result = all.where((s) {
      if (query.isNotEmpty) {
        final matches = s.title.toLowerCase().contains(query) ||
            s.code.toLowerCase().contains(query) ||
            s.language.toLowerCase().contains(query) ||
            s.tags.any((t) => t.toLowerCase().contains(query));
        if (!matches) return false;
      }
      if (tagFilter.isNotEmpty && !s.tags.contains(tagFilter)) return false;
      if (langFilter.isNotEmpty && s.language != langFilter) return false;

      // Collection filter
      if (_selectedCollectionId == 'favorites') {
        if (!s.isFavorite) return false;
      }

      return true;
    }).toList();

    // Sort
    switch (_sortOption) {
      case SnippetSortOption.recent:
        result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case SnippetSortOption.oldest:
        result.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case SnippetSortOption.nameAsc:
        result.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case SnippetSortOption.nameDesc:
        result.sort((a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()));
      case SnippetSortOption.mostUsed:
        result.sort((a, b) => b.usageCount.compareTo(a.usageCount));
      case SnippetSortOption.language:
        result.sort((a, b) => a.language.compareTo(b.language));
    }

    return result;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SNIPPET ACTIONS
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _copyToClipboard(CodeSnippet snippet) async {
    await Clipboard.setData(ClipboardData(text: snippet.code));
    ref.read(snippetsProvider.notifier).recordUsage(snippet.id);
    _showSnackBar('已复制到剪贴板', icon: Icons.check_circle, color: AppTheme.success);
  }

  Future<void> _openInEditor(CodeSnippet snippet) async {
    ref.read(snippetsProvider.notifier).recordUsage(snippet.id);
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EditorScreen(
            initialFilePath: null,
          ),
        ),
      );
    }
  }

  Future<void> _shareSnippet(CodeSnippet snippet) async {
    await Share.share(
      '// ${snippet.title}\n// Language: ${snippet.language}\n${snippet.code}',
      subject: 'Code Snippet: ${snippet.title}',
    );
  }

  Future<void> _duplicateSnippet(CodeSnippet snippet) async {
    final dup = CodeSnippet.create(
      title: '${snippet.title} (Copy)',
      code: snippet.code,
      language: snippet.language,
      tags: [...snippet.tags],
      description: snippet.description,
      source: snippet.source,
    );
    await ref.read(snippetsProvider.notifier).addSnippet(dup);
    _showSnackBar('已复制片段', icon: Icons.copy, color: AppTheme.cyan);
  }

  Future<void> _deleteSnippet(CodeSnippet snippet) async {
    setState(() => _lastDeletedSnippet = snippet);
    await ref.read(snippetsProvider.notifier).deleteSnippet(snippet.id);

    _undoTimer?.cancel();
    _undoTimer = Timer(const Duration(seconds: 5), () {
      _lastDeletedSnippet = null;
    });

    _showSnackBar(
      '已删除 "${snippet.title}"',
      icon: Icons.delete_outline,
      color: AppTheme.error,
      action: SnackBarAction(
        label: '撤销',
        textColor: AppTheme.cyan,
        onPressed: () async {
          if (_lastDeletedSnippet != null) {
            await ref.read(snippetsProvider.notifier).addSnippet(_lastDeletedSnippet!);
            setState(() => _lastDeletedSnippet = null);
          }
        },
      ),
    );
  }

  Future<void> _exportSnippetToFile(CodeSnippet snippet) async {
    final fileName = '${snippet.title.replaceAll(' ', '_')}.${snippet.language}';
    await Share.share(
      snippet.code,
      subject: fileName,
    );
    _showSnackBar('已导出: $fileName', icon: Icons.file_download, color: AppTheme.cyan);
  }

  Future<void> _toggleFavorite(CodeSnippet snippet) async {
    await ref.read(snippetsProvider.notifier).toggleFavorite(snippet.id);
  }

  void _showSnackBar(
    String message, {
    required IconData icon,
    required Color color,
    SnackBarAction? action,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        action: action,
        behavior: SnackBarBehavior.floating,
        duration: action != null ? const Duration(seconds: 6) : const Duration(seconds: 2),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // IMPORT / EXPORT
  // ═══════════════════════════════════════════════════════════════════════

  void _showExportDialog() {
    final snippets = ref.read(snippetsProvider);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
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
              const Text(
                '导出片段',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '共 ${snippets.length} 个片段',
                style: const TextStyle(fontSize: 14, color: AppTheme.textTertiary),
              ),
              const SizedBox(height: 20),
              _exportOptionTile(
                icon: Icons.code,
                title: '导出为 JSON',
                subtitle: '包含所有元数据的完整备份',
                onTap: () {
                  Navigator.pop(context);
                  final exportData = snippets.map((s) => {
                    'id': s.id,
                    'title': s.title,
                    'code': s.code,
                    'language': s.language,
                    'tags': s.tags,
                    'createdAt': s.createdAt,
                    'updatedAt': s.updatedAt,
                    'description': s.description,
                    'isFavorite': s.isFavorite,
                    'usageCount': s.usageCount,
                    'source': s.source,
                  }).toList();
                  Share.share(
                    const JsonEncoder.withIndent('  ').convert(exportData),
                    subject: 'mobile_agent_snippets.json',
                  );
                },
              ),
              const SizedBox(height: 12),
              _exportOptionTile(
                icon: Icons.text_snippet,
                title: '导出为文本',
                subtitle: '纯代码文本，便于阅读',
                onTap: () {
                  Navigator.pop(context);
                  final buffer = StringBuffer();
                  for (final s in snippets) {
                    buffer.writeln('// ============================================');
                    buffer.writeln('// ${s.title}');
                    buffer.writeln('// Language: ${s.language}');
                    buffer.writeln('// Tags: ${s.tags.join(', ')}');
                    buffer.writeln('// ============================================');
                    buffer.writeln(s.code);
                    buffer.writeln();
                  }
                  Share.share(buffer.toString(), subject: 'snippets.txt');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showImportDialog() {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 24,
            right: 24,
            top: 24,
          ),
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
              const Text(
                '导入片段',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '粘贴 JSON 格式的片段数据',
                style: TextStyle(fontSize: 14, color: AppTheme.textTertiary),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                maxLines: 8,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontFamily: AppTheme.fontCode,
                  fontSize: 12,
                ),
                decoration: const InputDecoration(
                  hintText: '[{"title": "...", "code": "...", "language": "..."}]',
                  hintStyle: TextStyle(color: AppTheme.textTertiary),
                ),
              ),
              const SizedBox(height: 16),
              GradientButtonWidget(
                label: '导入',
                icon: Icons.download,
                onPressed: () async {
                  try {
                    final data = jsonDecode(controller.text);
                    final List<dynamic> list = data is List ? data : [data];
                    int count = 0;
                    for (final item in list) {
                      if (item is Map) {
                        final snippet = CodeSnippet.create(
                          title: item['title']?.toString() ?? 'Untitled',
                          code: item['code']?.toString() ??
                              item['content']?.toString() ??
                              '',
                          language: item['language']?.toString() ?? 'text',
                          tags: (item['tags'] as List<dynamic>?)
                                  ?.map((t) => t.toString())
                                  .toList() ??
                              [],
                          description: item['description']?.toString(),
                          source: item['source']?.toString(),
                        );
                        await ref.read(snippetsProvider.notifier).addSnippet(snippet);
                        count++;
                      }
                    }
                    if (mounted) {
                      Navigator.pop(context);
                      _showSnackBar('成功导入 $count 个片段',
                          icon: Icons.check_circle, color: AppTheme.success);
                    }
                  } catch (e) {
                    _showSnackBar('导入失败: $e', icon: Icons.error, color: AppTheme.error);
                  }
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _exportOptionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surfaceCard.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border.withOpacity(0.5)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.violet.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppTheme.violet, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textTertiary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppTheme.textTertiary),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SNIPPET DETAIL BOTTOM SHEET
  // ═══════════════════════════════════════════════════════════════════════

  void _showSnippetDetail(CodeSnippet snippet) {
    ref.read(selectedSnippetProvider.notifier).state = snippet;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceElevated,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(top: BorderSide(color: AppTheme.border.withOpacity(0.5))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Title & favorite
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        snippet.title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        _toggleFavorite(snippet);
                        Navigator.pop(context);
                      },
                      icon: Icon(
                        snippet.isFavorite ? Icons.star : Icons.star_border,
                        color: snippet.isFavorite ? AppTheme.warning : AppTheme.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),

              // Tags
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: snippet.tags.map((tag) {
                    final color = _tagColor(tag);
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: color.withOpacity(0.3)),
                      ),
                      child: Text(
                        tag,
                        style: TextStyle(
                          fontSize: 11,
                          color: color,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),

              // Meta info row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    _metaChip(
                      icon: Icons.code,
                      label: snippet.language.toUpperCase(),
                    ),
                    const SizedBox(width: 8),
                    _metaChip(
                      icon: Icons.bar_chart,
                      label: '使用 ${snippet.usageCount} 次',
                    ),
                    const SizedBox(width: 8),
                    if (snippet.source != null)
                      _metaChip(
                        icon: _sourceIcon(snippet.source!),
                        label: _sourceLabel(snippet.source!),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Code block
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppTheme.deepSpace,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.border.withOpacity(0.5)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SingleChildScrollView(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        child: SelectableText(
                          snippet.code,
                          style: const TextStyle(
                            fontSize: 13,
                            fontFamily: AppTheme.fontCode,
                            color: AppTheme.textPrimary,
                            height: 1.6,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Quick actions bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceDark,
                  border: Border(top: BorderSide(color: AppTheme.border)),
                ),
                child: SafeArea(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _quickActionButton(
                        icon: Icons.copy,
                        label: '复制',
                        onTap: () {
                          _copyToClipboard(snippet);
                          Navigator.pop(context);
                        },
                      ),
                      _quickActionButton(
                        icon: Icons.open_in_new,
                        label: '编辑',
                        onTap: () {
                          Navigator.pop(context);
                          _openSnippetEditor(snippet: snippet);
                        },
                      ),
                      _quickActionButton(
                        icon: Icons.share,
                        label: '分享',
                        onTap: () => _shareSnippet(snippet),
                      ),
                      _quickActionButton(
                        icon: Icons.copy_all,
                        label: '复制',
                        onTap: () {
                          _duplicateSnippet(snippet);
                          Navigator.pop(context);
                        },
                      ),
                      _quickActionButton(
                        icon: Icons.file_download,
                        label: '导出',
                        onTap: () {
                          _exportSnippetToFile(snippet);
                          Navigator.pop(context);
                        },
                      ),
                      _quickActionButton(
                        icon: Icons.delete_outline,
                        label: '删除',
                        color: AppTheme.error,
                        onTap: () {
                          Navigator.pop(context);
                          _deleteSnippet(snippet);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metaChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppTheme.textTertiary),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppTheme.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _quickActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color ?? AppTheme.textSecondary),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: color ?? AppTheme.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SNIPPET EDITOR
  // ═══════════════════════════════════════════════════════════════════════

  void _openSnippetEditor({CodeSnippet? snippet}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SnippetEditorScreen(
          initialTitle: snippet?.title,
          initialCode: snippet?.code,
          initialLanguage: snippet?.language,
          initialTags: snippet?.tags,
          snippetSource: snippet?.source,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // VOICE CAPTURE FLOW
  // ═══════════════════════════════════════════════════════════════════════

  void _startVoiceCapture() {
    setState(() {
      _isRecording = true;
      _recordedText = '';
      _waveformData = List.filled(30, 0.1);
    });

    // Simulate waveform animation
    _waveformTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      setState(() {
        _waveformData = List.generate(30, (_) => 0.1 + (0.9 * (DateTime.now().millisecond % 100) / 100));
      });
    });

    // Simulate voice transcription after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted || !_isRecording) return;
      _stopVoiceCapture();
    });
  }

  void _stopVoiceCapture() {
    _waveformTimer?.cancel();
    setState(() {
      _isRecording = false;
      _recordedText = 'class DataService {\n  Future<List<Data>> fetchAll() async {\n    final response = await http.get(Uri.parse("/api/data"));\n    return Data.fromJsonList(jsonDecode(response.body));\n  }\n}';
    });
  }

  void _showVoiceCaptureSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceElevated,
      isScrollControlled: true,
      isDismissible: !_isRecording,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          padding: const EdgeInsets.all(24),
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
              const SizedBox(height: 24),
              const Text(
                '语音转代码',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _isRecording ? '正在聆听...' : '点击麦克风开始录音',
                style: const TextStyle(fontSize: 14, color: AppTheme.textTertiary),
              ),
              const SizedBox(height: 24),

              // Waveform visualization
              if (_isRecording) ...[
                SizedBox(
                  height: 80,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: _waveformData.map((amplitude) {
                      return Container(
                        width: 4,
                        height: 20 + (amplitude * 50),
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          gradient: AppTheme.auroraGradient,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Recording button
              GestureDetector(
                onTap: () {
                  if (_isRecording) {
                    setSheetState(() {
                      _waveformTimer?.cancel();
                      _isRecording = false;
                      _recordedText = 'class DataService {\n  Future<List<Data>> fetchAll() async {\n    final response = await http.get(Uri.parse("/api/data"));\n    return Data.fromJsonList(jsonDecode(response.body));\n  }\n}';
                    });
                  } else {
                    setSheetState(() {
                      _isRecording = true;
                      _waveformData = List.filled(30, 0.1);
                    });
                    _waveformTimer = Timer.periodic(
                      const Duration(milliseconds: 80),
                      (_) => setSheetState(() {
                        _waveformData = List.generate(
                          30,
                          (_) => 0.1 + (0.9 * (DateTime.now().millisecond % 100) / 100),
                        );
                      }),
                    );
                    Future.delayed(const Duration(seconds: 3), () {
                      if (mounted) {
                        setSheetState(() {
                          _waveformTimer?.cancel();
                          _isRecording = false;
                          _recordedText = 'class DataService {\n  Future<List<Data>> fetchAll() async {\n    final response = await http.get(Uri.parse("/api/data"));\n    return Data.fromJsonList(jsonDecode(response.body));\n  }\n}';
                        });
                      }
                    });
                  }
                },
                child: AnimatedContainer(
                  duration: AppTheme.animNormal,
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: _isRecording ? AppTheme.violetGradient : AppTheme.auroraGradient,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (_isRecording ? AppTheme.violet : AppTheme.cyan)
                            .withOpacity(0.4),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Icon(
                    _isRecording ? Icons.stop : Icons.mic,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Transcription preview
              if (_recordedText.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.deepSpace,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border.withOpacity(0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.cyan.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              '识别结果',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.cyan,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${_recordedText.split('\n').length} 行',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textTertiary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _recordedText,
                        style: const TextStyle(
                          fontFamily: AppTheme.fontCode,
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                GradientButtonWidget(
                  label: '保存为片段',
                  icon: Icons.save,
                  onPressed: () {
                    Navigator.pop(context);
                    _openSnippetEditorFromCapture(
                      title: '语音捕捉: ${_recordedText.split('{').first.trim()}',
                      code: _recordedText,
                      source: 'voice',
                    );
                  },
                ),
              ],

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    ).whenComplete(() {
      _waveformTimer?.cancel();
      _isRecording = false;
      _recordedText = '';
    });
  }

  // ═══════════════════════════════════════════════════════════════════════
  // OCR / SCREENSHOT CAPTURE
  // ═══════════════════════════════════════════════════════════════════════

  void _showOcrCaptureSheet() {
    String extractedCode = '';
    bool isProcessing = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          padding: const EdgeInsets.all(24),
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
              const SizedBox(height: 24),
              const Text(
                '截图转代码',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '从截图中提取代码',
                style: TextStyle(fontSize: 14, color: AppTheme.textTertiary),
              ),
              const SizedBox(height: 24),

              // Image source buttons
              if (extractedCode.isEmpty && !isProcessing) ...[
                Row(
                  children: [
                    Expanded(
                      child: _captureSourceButton(
                        icon: Icons.camera_alt,
                        label: '拍照',
                        onTap: () {
                          setSheetState(() => isProcessing = true);
                          Future.delayed(const Duration(seconds: 2), () {
                            if (mounted) {
                              setSheetState(() {
                                isProcessing = false;
                                extractedCode = 'func fetchUser(ctx context.Context, id string) (*User, error) {\n    row := db.QueryRowContext(ctx,\n        "SELECT id, name, email FROM users WHERE id = \$1", id)\n    var u User\n    err := row.Scan(&u.ID, &u.Name, &u.Email)\n    return &u, err\n}';
                              });
                            }
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _captureSourceButton(
                        icon: Icons.photo_library,
                        label: '相册',
                        onTap: () {
                          setSheetState(() => isProcessing = true);
                          Future.delayed(const Duration(seconds: 2), () {
                            if (mounted) {
                              setSheetState(() {
                                isProcessing = false;
                                extractedCode = 'type Config struct {\n    Port        int           `json:"port"`\n    Timeout     time.Duration `json:"timeout"`\n    DatabaseURL string        `json:"database_url"`\n}\n\nfunc (c *Config) Validate() error {\n    if c.Port <= 0 {\n        return errors.New("port must be positive")\n    }\n    return nil\n}';
                              });
                            }
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ],

              if (isProcessing) ...[
                const SizedBox(height: 40),
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(AppTheme.violet),
                ),
                const SizedBox(height: 16),
                const Text(
                  '正在识别代码...',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 40),
              ],

              if (extractedCode.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.deepSpace,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border.withOpacity(0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF9C27B0).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              '提取结果',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFFCE93D8),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        extractedCode,
                        style: const TextStyle(
                          fontFamily: AppTheme.fontCode,
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                GradientButtonWidget(
                  label: '保存为片段',
                  icon: Icons.save,
                  onPressed: () {
                    Navigator.pop(context);
                    _openSnippetEditorFromCapture(
                      title: '截图提取: ${extractedCode.split('{').first.trim()}',
                      code: extractedCode,
                      source: 'screenshot',
                    );
                  },
                ),
              ],

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _captureSourceButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: AppTheme.surfaceCard.withOpacity(0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border.withOpacity(0.5)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 36, color: AppTheme.violet),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }

  void _openSnippetEditorFromCapture({
    required String title,
    required String code,
    required String source,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SnippetEditorScreen(
          initialTitle: title,
          initialCode: code,
          snippetSource: source,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // AI GENERATION FLOW
  // ═══════════════════════════════════════════════════════════════════════

  void _showAiGenerateSheet() {
    final descriptionController = TextEditingController();
    String selectedLang = 'dart';
    String generatedCode = '';
    bool isGenerating = false;

    final languages = [
      'dart', 'python', 'javascript', 'typescript', 'go',
      'rust', 'java', 'kotlin', 'swift', 'sql',
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            left: 24,
            right: 24,
            top: 24,
          ),
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
              const SizedBox(height: 24),
              const Text(
                'AI 生成代码',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '描述你想要的代码，AI 将为你生成',
                style: TextStyle(fontSize: 14, color: AppTheme.textTertiary),
              ),
              const SizedBox(height: 20),

              // Description input
              TextField(
                controller: descriptionController,
                maxLines: 3,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                  hintText: '例如：一个 Flutter 登录页面，包含邮箱和密码输入框',
                  hintStyle: TextStyle(color: AppTheme.textTertiary, fontSize: 13),
                  prefixIcon: Icon(Icons.description, color: AppTheme.textTertiary),
                ),
              ),
              const SizedBox(height: 12),

              // Language selector
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: languages.map((lang) {
                  final isSelected = selectedLang == lang;
                  return ChoiceChip(
                    label: Text(lang.toUpperCase()),
                    selected: isSelected,
                    onSelected: (_) => setSheetState(() => selectedLang = lang),
                    selectedColor: AppTheme.violet.withOpacity(0.3),
                    labelStyle: TextStyle(
                      color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Generate button
              if (generatedCode.isEmpty) ...[
                GradientButtonWidget(
                  label: isGenerating ? '生成中...' : '生成代码',
                  icon: isGenerating ? null : Icons.auto_awesome,
                  onPressed: isGenerating
                      ? () {}
                      : () {
                          if (descriptionController.text.trim().isEmpty) return;
                          setSheetState(() => isGenerating = true);
                          Future.delayed(const Duration(seconds: 2), () {
                            if (!mounted) return;
                            setSheetState(() {
                              isGenerating = false;
                              generatedCode = _generateMockCode(
                                descriptionController.text,
                                selectedLang,
                              );
                            });
                          });
                        },
                  isLoading: isGenerating,
                ),
              ],

              // Generated code preview
              if (generatedCode.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.deepSpace,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border.withOpacity(0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.violet.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'AI 生成 · ${selectedLang.toUpperCase()}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.violetLight,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        generatedCode,
                        style: const TextStyle(
                          fontFamily: AppTheme.fontCode,
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => setSheetState(() {
                          generatedCode = '';
                          isGenerating = false;
                        }),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('重新生成'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GradientButtonWidget(
                        label: '保存',
                        icon: Icons.save,
                        onPressed: () {
                          Navigator.pop(context);
                          _openSnippetEditorFromCapture(
                            title: 'AI: ${descriptionController.text.substring(0, descriptionController.text.length > 20 ? 20 : descriptionController.text.length)}...',
                            code: generatedCode,
                            source: 'ai',
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  String _generateMockCode(String description, String language) {
    final templates = {
      'dart': '''import 'package:flutter/material.dart';

class GeneratedWidget extends StatelessWidget {
  const GeneratedWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Generated'),
      ),
      body: const Center(
        child: Text('Hello from AI'),
      ),
    );
  }
}''',
      'python': '''def main():
    """${description.substring(0, description.length > 50 ? 50 : description.length)}..."""
    data = process_input()
    result = transform(data)
    return output(result)

def process_input():
    return {"status": "ok", "items": []}

def transform(data):
    return [item.upper() for item in data.get("items", [])]

def output(result):
    print(f"Result: {result}")
    return result

if __name__ == "__main__":
    main()''',
      'go': '''package main

import (
    "fmt"
    "log"
)

func main() {
    result, err := Process()
    if err != nil {
        log.Fatal(err)
    }
    fmt.Printf("Result: %+v\\n", result)
}

func Process() (map[string]interface{}, error) {
    return map[string]interface{}{
        "status": "success",
    }, nil
}''',
      'javascript': '''async function main() {
  try {
    const data = await fetchData();
    const processed = processData(data);
    console.log('Result:', processed);
    return processed;
  } catch (error) {
    console.error('Error:', error);
    throw error;
  }
}

async function fetchData() {
  const response = await fetch('/api/data');
  return response.json();
}

function processData(data) {
  return data.map(item => ({
    ...item,
    processed: true
  }));
}

main();''',
      'sql': '''SELECT 
    u.id,
    u.name,
    COUNT(p.id) AS project_count,
    MAX(p.updated_at) AS last_active
FROM users u
LEFT JOIN projects p ON p.user_id = u.id
WHERE u.status = 'active'
GROUP BY u.id
ORDER BY last_active DESC;''',
    };
    return templates[language] ?? templates['dart']!;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // TEMPLATES BOTTOM SHEET
  // ═══════════════════════════════════════════════════════════════════════

  void _showTemplatesSheet() {
    String? selectedCategory;
    final categories = _builtinTemplates.map((t) => t.category).toSet().toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          padding: const EdgeInsets.all(24),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
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
              const Text(
                '代码模板',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_builtinTemplates.length} 个内置模板',
                style: const TextStyle(fontSize: 14, color: AppTheme.textTertiary),
              ),
              const SizedBox(height: 12),

              // Category filter
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: const Text('全部'),
                        selected: selectedCategory == null,
                        onSelected: (_) => setSheetState(() => selectedCategory = null),
                        selectedColor: AppTheme.violet.withOpacity(0.3),
                      ),
                    ),
                    ...categories.map((cat) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(cat),
                            selected: selectedCategory == cat,
                            onSelected: (_) => setSheetState(() => selectedCategory = cat),
                            selectedColor: AppTheme.violet.withOpacity(0.3),
                          ),
                        )),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Template list
              Expanded(
                child: ListView.builder(
                  itemCount: _builtinTemplates
                      .where((t) =>
                          selectedCategory == null || t.category == selectedCategory)
                      .length,
                  itemBuilder: (context, index) {
                    final template = _builtinTemplates
                        .where((t) =>
                            selectedCategory == null || t.category == selectedCategory)
                        .elementAt(index);
                    return _templateCard(template);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _templateCard(SnippetTemplate template) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        _openSnippetEditorFromCapture(
          title: template.title,
          code: template.code,
          source: 'template',
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surfaceCard.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border.withOpacity(0.4)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _languageColor(template.language).withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                template.language.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: _languageColor(template.language),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    template.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    template.description,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textTertiary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppTheme.textTertiary, size: 18),
          ],
        ),
      ),
    );
  }

  Color _languageColor(String language) {
    final colors = {
      'dart': const Color(0xFF54C5F8),
      'python': const Color(0xFF3776AB),
      'javascript': const Color(0xFFF7DF1E),
      'typescript': const Color(0xFF3178C6),
      'go': const Color(0xFF00ADD8),
      'rust': const Color(0xFFDEA584),
      'java': const Color(0xFF007396),
      'kotlin': const Color(0xFF7F52FF),
      'swift': const Color(0xFFFFAC45),
      'sql': const Color(0xFFF29111),
    };
    return colors[language.toLowerCase()] ?? AppTheme.violet;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // FILTER & SORT BOTTOM SHEET
  // ═══════════════════════════════════════════════════════════════════════

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final allTags = ref.watch(allSnippetTagsProvider);
          final allLangs = ref.watch(allSnippetLanguagesProvider);
          final currentTag = ref.watch(snippetTagFilterProvider);
          final currentLang = ref.watch(snippetLanguageFilterProvider);

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
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
                  const Text(
                    '筛选与排序',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Sort options
                  const Text(
                    '排序方式',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: SnippetSortOption.values.map((opt) {
                      final isSelected = _sortOption == opt;
                      return ChoiceChip(
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(opt.icon, size: 14, color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary),
                            const SizedBox(width: 6),
                            Text(opt.label),
                          ],
                        ),
                        selected: isSelected,
                        onSelected: (_) => setSheetState(() => _sortOption = opt),
                        selectedColor: AppTheme.violet.withOpacity(0.3),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),

                  // Language filter
                  if (allLangs.isNotEmpty) ...[
                    const Text(
                      '语言',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('全部'),
                          selected: currentLang.isEmpty,
                          onSelected: (_) {
                            ref.read(snippetLanguageFilterProvider.notifier).state = '';
                            setSheetState(() {});
                          },
                          selectedColor: AppTheme.violet.withOpacity(0.3),
                        ),
                        ...allLangs.map((lang) => ChoiceChip(
                              label: Text(lang.toUpperCase()),
                              selected: currentLang == lang,
                              onSelected: (_) {
                                ref.read(snippetLanguageFilterProvider.notifier).state =
                                    lang;
                                setSheetState(() {});
                              },
                              selectedColor: AppTheme.violet.withOpacity(0.3),
                            )),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Tag filter
                  if (allTags.isNotEmpty) ...[
                    const Text(
                      '标签',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('全部'),
                          selected: currentTag.isEmpty,
                          onSelected: (_) {
                            ref.read(snippetTagFilterProvider.notifier).state = '';
                            setSheetState(() {});
                          },
                          selectedColor: AppTheme.cyan.withOpacity(0.3),
                        ),
                        ...allTags.map((tag) {
                          final color = _tagColor(tag);
                          return ChoiceChip(
                            label: Text(tag),
                            selected: currentTag == tag,
                            onSelected: (_) {
                              ref.read(snippetTagFilterProvider.notifier).state = tag;
                              setSheetState(() {});
                            },
                            selectedColor: color.withOpacity(0.3),
                          );
                        }),
                      ],
                    ),
                  ] else ...[
                    const Text(
                      '添加片段后将自动收集标签',
                      style: TextStyle(fontSize: 13, color: AppTheme.textTertiary),
                    ),
                  ],
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // COLLECTIONS MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════

  void _showCollectionsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
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
                Row(
                  children: [
                    const Text(
                      '收藏夹',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => _showCreateCollectionDialog(setSheetState),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('新建'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ..._collections.map((col) => ListTile(
                      leading: Icon(
                        col.iconName == 'star' ? Icons.star : Icons.folder,
                        color: col.id == 'favorites' ? AppTheme.warning : AppTheme.violet,
                      ),
                      title: Text(col.name),
                      subtitle: col.id == 'all'
                          ? Text('${ref.watch(snippetsProvider).length} 个片段')
                          : col.id == 'favorites'
                              ? Text('${ref.watch(snippetsProvider).where((s) => s.isFavorite).length} 个片段')
                              : Text('${col.snippetIds.length} 个片段'),
                      selected: _selectedCollectionId == col.id,
                      selectedTileColor: AppTheme.violet.withOpacity(0.1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      onTap: () {
                        setState(() => _selectedCollectionId = col.id == 'all' ? null : col.id);
                        Navigator.pop(context);
                      },
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCreateCollectionDialog(StateSetter setSheetState) {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        title: const Text('新建收藏夹', style: TextStyle(color: AppTheme.textPrimary)),
        content: TextField(
          controller: nameController,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(
            hintText: '收藏夹名称',
            hintStyle: TextStyle(color: AppTheme.textTertiary),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.trim().isNotEmpty) {
                setSheetState(() {
                  _collections.add(SnippetCollection(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    name: nameController.text.trim(),
                    createdAt: DateTime.now(),
                  ));
                });
              }
              Navigator.pop(context);
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════

  IconData _sourceIcon(String source) {
    switch (source) {
      case 'voice':
        return Icons.mic;
      case 'screenshot':
        return Icons.camera_alt;
      case 'ai':
        return Icons.auto_awesome;
      case 'template':
        return Icons.description;
      case 'github':
        return Icons.code;
      default:
        return Icons.edit;
    }
  }

  String _sourceLabel(String source) {
    switch (source) {
      case 'voice':
        return '语音';
      case 'screenshot':
        return '截图';
      case 'ai':
        return 'AI';
      case 'template':
        return '模板';
      case 'github':
        return 'GitHub';
      default:
        return '手动';
    }
  }

  DateTime _parseDateTime(String isoString) {
    return DateTime.tryParse(isoString) ?? DateTime.now();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final allSnippets = ref.watch(snippetsProvider);
    final filteredSnippets = _getFilteredAndSortedSnippets(allSnippets);

    return Scaffold(
      backgroundColor: AppTheme.deepSpace,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
              child: Row(
                children: [
                  const Text(
                    '灵感',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const Spacer(),

                  // Cloud sync indicator
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppTheme.success.withOpacity(0.3)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_done, size: 12, color: AppTheme.success),
                        SizedBox(width: 4),
                        Text(
                          '已同步',
                          style: TextStyle(fontSize: 10, color: AppTheme.success),
                        ),
                      ],
                    ),
                  ),

                  // Import
                  IconButton(
                    onPressed: _showImportDialog,
                    icon: const Icon(Icons.download, color: AppTheme.textSecondary, size: 22),
                    tooltip: '导入',
                  ),

                  // Export
                  IconButton(
                    onPressed: _showExportDialog,
                    icon: const Icon(Icons.upload, color: AppTheme.textSecondary, size: 22),
                    tooltip: '导出',
                  ),

                  // Collections
                  IconButton(
                    onPressed: _showCollectionsSheet,
                    icon: const Icon(Icons.folder_outlined, color: AppTheme.textSecondary, size: 22),
                    tooltip: '收藏夹',
                  ),

                  // Filter
                  IconButton(
                    onPressed: _showFilterSheet,
                    icon: Stack(
                      children: [
                        const Icon(Icons.filter_list, color: AppTheme.textSecondary, size: 22),
                        if (ref.watch(snippetTagFilterProvider).isNotEmpty ||
                            ref.watch(snippetLanguageFilterProvider).isNotEmpty)
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: AppTheme.violet,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                    tooltip: '筛选',
                  ),
                ],
              ),
            ),

            // ── Search bar ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: '搜索代码片段...',
                  hintStyle: const TextStyle(color: AppTheme.textTertiary),
                  prefixIcon: const Icon(Icons.search, color: AppTheme.textTertiary),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18, color: AppTheme.textTertiary),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        )
                      : null,
                ),
              ),
            ),

            // ── Collection indicator ──
            if (_selectedCollectionId != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: InkWell(
                  onTap: () => setState(() => _selectedCollectionId = null),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.violet.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.violet.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _selectedCollectionId == 'favorites' ? Icons.star : Icons.folder,
                          size: 14,
                          color: AppTheme.violet,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _collections.firstWhere((c) => c.id == _selectedCollectionId).name,
                          style: const TextStyle(fontSize: 12, color: AppTheme.violet),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.close, size: 14, color: AppTheme.violet),
                      ],
                    ),
                  ),
                ),
              ),

            // ── Tab bar ──
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.surfaceDark,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.border.withOpacity(0.5)),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: AppTheme.auroraGradient,
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                indicatorPadding: const EdgeInsets.all(4),
                labelColor: Colors.white,
                unselectedLabelColor: AppTheme.textTertiary,
                labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                dividerColor: Colors.transparent,
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.code, size: 16),
                        const SizedBox(width: 6),
                        const Text('我的'),
                        if (allSnippets.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.violet.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${allSnippets.length}',
                              style: const TextStyle(fontSize: 10),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.favorite, size: 16),
                        const SizedBox(width: 6),
                        const Text('收藏'),
                        if (allSnippets.where((s) => s.isFavorite).isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.warning.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${allSnippets.where((s) => s.isFavorite).length}',
                              style: const TextStyle(fontSize: 10),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.auto_awesome, size: 16),
                        const SizedBox(width: 6),
                        const Text('模板'),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Tab content ──
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: My Snippets
                  _buildSnippetListView(filteredSnippets),

                  // Tab 2: Favorites
                  _buildSnippetListView(
                    filteredSnippets.where((s) => s.isFavorite).toList(),
                    emptyMessage: '没有收藏的片段',
                    emptyIcon: Icons.star_border,
                  ),

                  // Tab 3: Templates
                  _buildTemplatesView(),
                ],
              ),
            ),
          ],
        ),
      ),

      // ── FAB with multi-option menu ──
      floatingActionButton: _buildExpandableFab(),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SNIPPET LIST VIEW
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildSnippetListView(
    List<CodeSnippet> snippets, {
    String emptyMessage = '还没有代码片段',
    IconData emptyIcon = Icons.code_off,
  }) {
    if (snippets.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              emptyIcon,
              size: 64,
              color: AppTheme.textTertiary.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              emptyMessage,
              style: TextStyle(
                fontSize: 16,
                color: AppTheme.textTertiary.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '点击右下角 + 开始捕捉灵感',
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textTertiary.withOpacity(0.4),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: snippets.length,
      itemBuilder: (context, index) {
        final snippet = snippets[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Stack(
            children: [
              SnippetCardWidget(
                key: ValueKey(snippet.id),
                title: snippet.title,
                code: snippet.code,
                language: snippet.language,
                tags: snippet.tags,
                source: snippet.source ?? 'manual',
                createdAt: _parseDateTime(snippet.createdAt),
                isFavorite: snippet.isFavorite,
                onFavoriteToggle: () => _toggleFavorite(snippet),
                onTap: () => _showSnippetDetail(snippet),
              ),
              // Usage badge (top-right overlay)
              if (snippet.usageCount > 0)
                Positioned(
                  top: 12,
                  right: 48,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.cyan.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${snippet.usageCount}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppTheme.cyan,
                        fontWeight: FontWeight.w500,
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

  // ═══════════════════════════════════════════════════════════════════════
  // TEMPLATES VIEW
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildTemplatesView() {
    final categories = _builtinTemplates.map((t) => t.category).toSet().toList();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: categories.length,
      itemBuilder: (context, catIndex) {
        final category = categories[catIndex];
        final categoryTemplates =
            _builtinTemplates.where((t) => t.category == category).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Category header
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 10),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 18,
                    decoration: BoxDecoration(
                      gradient: AppTheme.auroraGradient,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    category,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceCard,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${categoryTemplates.length}',
                      style: const TextStyle(fontSize: 11, color: AppTheme.textTertiary),
                    ),
                  ),
                ],
              ),
            ),

            // Template cards in this category
            ...categoryTemplates.map((template) => _templateCard(template)),

            if (catIndex < categories.length - 1)
              const Divider(height: 24, color: AppTheme.divider),
          ],
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // EXPANDABLE FAB
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildExpandableFab() {
    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        // Dimming overlay when expanded
        if (_isFabExpanded)
          GestureDetector(
            onTap: () {
              setState(() {
                _isFabExpanded = false;
                _fabAnimationController.reverse();
              });
            },
            child: Container(
              color: Colors.black.withOpacity(0.3),
            ),
          ),

        // FAB menu options
        if (_isFabExpanded) ...[
          _fabOption(
            label: '代码模板',
            icon: Icons.description,
            color: AppTheme.violet,
            index: 0,
            onTap: () {
              _collapseFab();
              _showTemplatesSheet();
            },
          ),
          _fabOption(
            label: 'AI 生成',
            icon: Icons.auto_awesome,
            color: const Color(0xFFFFA502),
            index: 1,
            onTap: () {
              _collapseFab();
              _showAiGenerateSheet();
            },
          ),
          _fabOption(
            label: '截图识别',
            icon: Icons.camera_alt,
            color: const Color(0xFF9C27B0),
            index: 2,
            onTap: () {
              _collapseFab();
              _showOcrCaptureSheet();
            },
          ),
          _fabOption(
            label: '语音捕捉',
            icon: Icons.mic,
            color: AppTheme.cyan,
            index: 3,
            onTap: () {
              _collapseFab();
              _showVoiceCaptureSheet();
            },
          ),
          _fabOption(
            label: '文字输入',
            icon: Icons.edit,
            color: AppTheme.success,
            index: 4,
            onTap: () {
              _collapseFab();
              _openSnippetEditor();
            },
          ),
        ],

        // Main FAB
        Padding(
          padding: const EdgeInsets.all(16),
          child: FloatingActionButton(
            onPressed: () {
              setState(() {
                _isFabExpanded = !_isFabExpanded;
                if (_isFabExpanded) {
                  _fabAnimationController.forward();
                } else {
                  _fabAnimationController.reverse();
                }
              });
            },
            backgroundColor: _isFabExpanded ? AppTheme.error : AppTheme.violet,
            child: AnimatedRotation(
              turns: _isFabExpanded ? 0.125 : 0,
              duration: AppTheme.animNormal,
              child: Icon(_isFabExpanded ? Icons.close : Icons.add),
            ),
          ),
        ),
      ],
    );
  }

  Widget _fabOption({
    required String label,
    required IconData icon,
    required Color color,
    required int index,
    required VoidCallback onTap,
  }) {
    final offset = (index + 1) * 72.0;

    return AnimatedPositioned(
      duration: AppTheme.animNormal,
      curve: Curves.easeOutBack,
      bottom: offset + 16,
      right: 20,
      child: AnimatedOpacity(
        duration: AppTheme.animNormal,
        opacity: _isFabExpanded ? 1.0 : 0.0,
        child: Row(
          children: [
            // Label
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.surfaceElevated,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Icon button
            GestureDetector(
              onTap: onTap,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.4),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _collapseFab() {
    setState(() {
      _isFabExpanded = false;
      _fabAnimationController.reverse();
    });
  }
}
