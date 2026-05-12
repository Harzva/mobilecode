import 'package:flutter/material.dart';
import '../themes/app_theme.dart';
import '../widgets/file_tree_widget.dart';
import '../models/project_model.dart';
import 'editor_screen.dart';

/// Project detail screen with file tree sidebar and editor
/// Split view: Left 30% file tree, Right 70% editor
class ProjectDetailScreen extends StatefulWidget {
  final String projectName;
  final String language;

  const ProjectDetailScreen({
    super.key,
    required this.projectName,
    required this.language,
  });

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  FileNode? _selectedFile;
  final List<String> _breadcrumb = [];
  bool _sidebarVisible = true;

  // Demo file tree data
  late List<FileNode> _fileTree;

  @override
  void initState() {
    super.initState();
    _fileTree = _buildDemoFileTree();
    _breadcrumb.add(widget.projectName);
  }

  List<FileNode> _buildDemoFileTree() {
    return [
      FileNode(
        id: 'lib',
        name: 'lib',
        path: 'lib',
        isDirectory: true,
        isExpanded: true,
        modifiedAt: DateTime.now(),
        children: [
          FileNode(
            id: 'main.dart',
            name: 'main.dart',
            path: 'lib/main.dart',
            modifiedAt: DateTime.now(),
            content: '''import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const MobileAgentApp());
}

class MobileAgentApp extends StatelessWidget {
  const MobileAgentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mobile Agent',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const HomeScreen(),
    );
  }
}''',
          ),
          FileNode(
            id: 'screens',
            name: 'screens',
            path: 'lib/screens',
            isDirectory: true,
            modifiedAt: DateTime.now(),
            children: [
              FileNode(
                id: 'home.dart',
                name: 'home_screen.dart',
                path: 'lib/screens/home_screen.dart',
                modifiedAt: DateTime.now(),
                content: 'class HomeScreen extends StatelessWidget {\n  const HomeScreen({super.key});\n\n  @override\n  Widget build(BuildContext context) {\n    return Scaffold(\n      appBar: AppBar(title: const Text(\'Home\')),\n      body: const Center(child: Text(\'Welcome\')),\n    );\n  }\n}',
              ),
              FileNode(
                id: 'editor.dart',
                name: 'editor_screen.dart',
                path: 'lib/screens/editor_screen.dart',
                modifiedAt: DateTime.now(),
                content: '// Editor screen implementation',
              ),
              FileNode(
                id: 'settings.dart',
                name: 'settings_screen.dart',
                path: 'lib/screens/settings_screen.dart',
                modifiedAt: DateTime.now(),
                content: '// Settings screen implementation',
              ),
            ],
          ),
          FileNode(
            id: 'widgets',
            name: 'widgets',
            path: 'lib/widgets',
            isDirectory: true,
            modifiedAt: DateTime.now(),
            children: [
              FileNode(
                id: 'sidebar.dart',
                name: 'sidebar_widget.dart',
                path: 'lib/widgets/sidebar_widget.dart',
                modifiedAt: DateTime.now(),
                content: '// Sidebar widget implementation',
              ),
              FileNode(
                id: 'card.dart',
                name: 'glass_card_widget.dart',
                path: 'lib/widgets/glass_card_widget.dart',
                modifiedAt: DateTime.now(),
                content: '// Glass card widget implementation',
              ),
            ],
          ),
          FileNode(
            id: 'models',
            name: 'models',
            path: 'lib/models',
            isDirectory: true,
            modifiedAt: DateTime.now(),
            children: [
              FileNode(
                id: 'project.dart',
                name: 'project_model.dart',
                path: 'lib/models/project_model.dart',
                modifiedAt: DateTime.now(),
                content: '// Project model definition',
              ),
            ],
          ),
        ],
      ),
      FileNode(
        id: 'test',
        name: 'test',
        path: 'test',
        isDirectory: true,
        modifiedAt: DateTime.now(),
        children: [
          FileNode(
            id: 'widget_test.dart',
            name: 'widget_test.dart',
            path: 'test/widget_test.dart',
            modifiedAt: DateTime.now(),
            content: '// Widget tests',
          ),
        ],
      ),
      FileNode(
        id: 'pubspec.yaml',
        name: 'pubspec.yaml',
        path: 'pubspec.yaml',
        modifiedAt: DateTime.now(),
        content: '''name: mobile_agent\ndescription: AI-powered mobile code editor\npublish_to: 'none'\nversion: 1.0.0+1\n\nenvironment:\n  sdk: '>=3.0.0 <4.0.0'\n\ndependencies:\n  flutter:\n    sdk: flutter\n  cupertino_icons: ^1.0.2\n''',
      ),
      FileNode(
        id: 'README.md',
        name: 'README.md',
        path: 'README.md',
        modifiedAt: DateTime.now(),
        content: '# Mobile Agent\n\nAI-powered mobile code editor.',
      ),
      FileNode(
        id: '.gitignore',
        name: '.gitignore',
        path: '.gitignore',
        modifiedAt: DateTime.now(),
        content: '# Build outputs\nbuild/\n.dart_tool/\n\n# IDE\n.idea/\n.vscode/',
      ),
    ];
  }

  void _onFileSelected(FileNode node) {
    if (node.isDirectory) {
      setState(() {
        node.isExpanded = !node.isExpanded;
      });
      // Update breadcrumb
      _updateBreadcrumb(node);
    } else {
      setState(() {
        _selectedFile = node;
        _updateBreadcrumb(node);
      });
    }
  }

  void _updateBreadcrumb(FileNode node) {
    _breadcrumb.clear();
    _breadcrumb.add(widget.projectName);
    final parts = node.path.split('/');
    for (int i = 0; i < parts.length; i++) {
      if (parts[i].isNotEmpty && i > 0) {
        _breadcrumb.add(parts[i]);
      } else if (parts[i].isNotEmpty && parts.length == 1) {
        _breadcrumb.add(parts[i]);
      }
    }
  }

  void _showNewFileDialog() {
    final nameController = TextEditingController();
    bool isDirectory = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
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
                  '新建文件/文件夹',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  autofocus: true,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    labelText: '名称',
                    labelStyle: TextStyle(color: AppTheme.textSecondary),
                    hintText: '例如: new_file.dart',
                    hintStyle: TextStyle(color: AppTheme.textTertiary),
                  ),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text(
                    '创建为文件夹',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                  value: isDirectory,
                  onChanged: (v) => setModalState(() => isDirectory = v),
                  activeColor: AppTheme.violet,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      if (nameController.text.isNotEmpty) {
                        setState(() {
                          _fileTree.add(FileNode(
                            id: DateTime.now().millisecondsSinceEpoch.toString(),
                            name: nameController.text,
                            path: nameController.text,
                            isDirectory: isDirectory,
                            modifiedAt: DateTime.now(),
                          ));
                        });
                        Navigator.pop(context);
                      }
                    },
                    child: const Text('创建'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.deepSpace,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar with breadcrumb
            _buildTopBar(),

            // Main content
            Expanded(
              child: Row(
                children: [
                  // Sidebar (file tree)
                  if (_sidebarVisible)
                    Container(
                      width: MediaQuery.of(context).size.width * 0.35,
                      decoration: const BoxDecoration(
                        color: AppTheme.surfaceDark,
                        border: Border(
                          right: BorderSide(color: AppTheme.divider),
                        ),
                      ),
                      child: Column(
                        children: [
                          // File tree header
                          Container(
                            height: 40,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: const BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: AppTheme.divider),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.folder_open,
                                  size: 16,
                                  color: AppTheme.textTertiary,
                                ),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    '文件',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: _showNewFileDialog,
                                  icon: const Icon(
                                    Icons.add,
                                    size: 18,
                                    color: AppTheme.textTertiary,
                                  ),
                                  tooltip: '新建文件',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 32,
                                    minHeight: 32,
                                  ),
                                ),
                                IconButton(
                                  onPressed: () {},
                                  icon: const Icon(
                                    Icons.refresh,
                                    size: 18,
                                    color: AppTheme.textTertiary,
                                  ),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 32,
                                    minHeight: 32,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // File tree
                          Expanded(
                            child: FileTreeWidget(
                              nodes: _fileTree,
                              selectedId: _selectedFile?.id,
                              onNodeTap: _onFileSelected,
                              onNodeLongPress: (node) => _showFileContextMenu(node),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Editor area
                  Expanded(
                    child: _selectedFile != null && !_selectedFile!.isDirectory
                        ? _buildEditorArea()
                        : _buildEmptyState(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),

      // FAB for new file
      floatingActionButton: FloatingActionButton(
        onPressed: _showNewFileDialog,
        mini: true,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 48,
      decoration: const BoxDecoration(
        color: AppTheme.surfaceDark,
        border: Border(
          bottom: BorderSide(color: AppTheme.divider),
        ),
      ),
      child: Row(
        children: [
          // Toggle sidebar
          IconButton(
            onPressed: () => setState(() => _sidebarVisible = !_sidebarVisible),
            icon: Icon(
              _sidebarVisible ? Icons.menu_open : Icons.menu,
              size: 20,
              color: AppTheme.textSecondary,
            ),
            tooltip: '切换侧边栏',
          ),

          // Back button
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, size: 20),
            color: AppTheme.textSecondary,
          ),

          // Breadcrumb
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (int i = 0; i < _breadcrumb.length; i++) ...[
                    if (i > 0)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: AppTheme.textTertiary,
                        ),
                      ),
                    GestureDetector(
                      onTap: () {},
                      child: Text(
                        _breadcrumb[i],
                        style: TextStyle(
                          fontSize: 13,
                          color: i == _breadcrumb.length - 1
                              ? AppTheme.textPrimary
                              : AppTheme.textSecondary,
                          fontWeight: i == _breadcrumb.length - 1
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Actions
          if (_selectedFile != null && !_selectedFile!.isDirectory) ...[
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.save, size: 20),
              color: AppTheme.textSecondary,
              tooltip: '保存',
            ),
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.share, size: 20),
              color: AppTheme.textSecondary,
              tooltip: '分享',
            ),
          ],
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildEditorArea() {
    return EditorScreen(
      key: ValueKey(_selectedFile!.id),
      initialContent: _selectedFile!.content ?? '',
      fileName: _selectedFile!.name,
      language: _selectedFile!.language,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.code_off,
            size: 64,
            color: AppTheme.textTertiary.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            '选择一个文件开始编辑',
            style: TextStyle(
              fontSize: 16,
              color: AppTheme.textTertiary.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '或者创建一个新文件',
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textTertiary.withOpacity(0.4),
            ),
          ),
        ],
      ),
    );
  }

  void _showFileContextMenu(FileNode node) {
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
              ListTile(
                leading: const Icon(Icons.open_in_new, color: AppTheme.cyan),
                title: const Text('打开', style: TextStyle(color: AppTheme.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  _onFileSelected(node);
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit, color: AppTheme.textSecondary),
                title: const Text('重命名', style: TextStyle(color: AppTheme.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  _renameNode(node);
                },
              ),
              if (!node.isDirectory)
                ListTile(
                  leading: const Icon(Icons.copy, color: AppTheme.textSecondary),
                  title: const Text('复制路径', style: TextStyle(color: AppTheme.textPrimary)),
                  onTap: () => Navigator.pop(context),
                ),
              const Divider(color: AppTheme.divider),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppTheme.error),
                title: const Text('删除', style: TextStyle(color: AppTheme.error)),
                onTap: () {
                  Navigator.pop(context);
                  _deleteNode(node);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _renameNode(FileNode node) {
    final controller = TextEditingController(text: node.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        title: const Text('重命名', style: TextStyle(color: AppTheme.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(
            hintText: '新名称',
            hintStyle: TextStyle(color: AppTheme.textTertiary),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                setState(() {
                  node.name = controller.text;
                });
              }
              Navigator.pop(context);
            },
            child: const Text('确定', style: TextStyle(color: AppTheme.cyan)),
          ),
        ],
      ),
    );
  }

  void _deleteNode(FileNode node) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        title: const Text('删除', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text(
          '确定要删除 "${node.name}" 吗？',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _fileTree.removeWhere((n) => n.id == node.id);
                if (_selectedFile?.id == node.id) {
                  _selectedFile = null;
                }
              });
              Navigator.pop(context);
            },
            child: const Text('删除', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
  }
}
