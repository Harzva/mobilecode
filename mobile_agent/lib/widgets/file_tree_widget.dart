import 'package:flutter/material.dart';
import '../themes/app_theme.dart';
import '../models/project_model.dart';

/// File tree navigator widget
/// Recursive folder/file rendering with expand/collapse
/// File icons by extension, context menu support
class FileTreeWidget extends StatelessWidget {
  final List<FileNode> nodes;
  final String? selectedId;
  final Function(FileNode)? onNodeTap;
  final Function(FileNode)? onNodeLongPress;
  final Function(FileNode, FileNode)? onNodeDrag; // source, target

  const FileTreeWidget({
    super.key,
    required this.nodes,
    this.selectedId,
    this.onNodeTap,
    this.onNodeLongPress,
    this.onNodeDrag,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: nodes.length,
      itemBuilder: (context, index) {
        return _FileTreeNode(
          key: ValueKey(nodes[index].id),
          node: nodes[index],
          selectedId: selectedId,
          depth: 0,
          onTap: onNodeTap,
          onLongPress: onNodeLongPress,
        );
      },
    );
  }
}

class _FileTreeNode extends StatelessWidget {
  final FileNode node;
  final String? selectedId;
  final int depth;
  final Function(FileNode)? onTap;
  final Function(FileNode)? onLongPress;

  const _FileTreeNode({
    super.key,
    required this.node,
    this.selectedId,
    required this.depth,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = node.id == selectedId;
    final indent = depth * 16.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Node row
        GestureDetector(
          onTap: () => onTap?.call(node),
          onLongPress: () => onLongPress?.call(node),
          child: Container(
            height: 36,
            margin: EdgeInsets.only(left: indent, right: 4),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.violet.withOpacity(0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: isSelected
                  ? Border.all(color: AppTheme.violet.withOpacity(0.3), width: 0.5)
                  : null,
            ),
            child: Row(
              children: [
                // Expand/collapse icon (for directories)
                SizedBox(
                  width: 24,
                  child: node.isDirectory
                      ? AnimatedRotation(
                          turns: node.isExpanded ? 0.25 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            Icons.chevron_right,
                            size: 16,
                            color: isSelected
                                ? AppTheme.violetLight
                                : AppTheme.textTertiary,
                          ),
                        )
                      : const SizedBox(width: 24),
                ),

                // File/Folder icon
                _buildNodeIcon(isSelected),
                const SizedBox(width: 8),

                // Node name
                Expanded(
                  child: Text(
                    node.name,
                    style: TextStyle(
                      fontSize: 13,
                      color: isSelected
                          ? AppTheme.violetLight
                          : AppTheme.textPrimary,
                      fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Children (if expanded directory)
        if (node.isDirectory && node.isExpanded && node.children.isNotEmpty)
          ...node.children.map(
            (child) => _FileTreeNode(
              key: ValueKey(child.id),
              node: child,
              selectedId: selectedId,
              depth: depth + 1,
              onTap: onTap,
              onLongPress: onLongPress,
            ),
          ),
      ],
    );
  }

  Widget _buildNodeIcon(bool isSelected) {
    final color = isSelected ? AppTheme.violetLight : AppTheme.textSecondary;
    final size = 18.0;

    if (node.isDirectory) {
      return Icon(
        node.isExpanded ? Icons.folder_open : Icons.folder,
        size: size,
        color: isSelected ? AppTheme.violet.withOpacity(0.8) : AppTheme.warning,
      );
    }

    // File icons by extension
    final ext = node.extension?.toLowerCase() ?? '';
    final iconData = _fileIconMap[ext];
    final iconColor = _fileColorMap[ext] ?? color;

    if (iconData != null) {
      return Icon(iconData, size: size, color: iconColor);
    }

    return Icon(
      Icons.insert_drive_file_outlined,
      size: size,
      color: color,
    );
  }

  // File icon mappings
  static final Map<String, IconData> _fileIconMap = {
    'dart': Icons.flutter_dash,
    'js': Icons.javascript,
    'ts': Icons.javascript,
    'json': Icons.data_object,
    'html': Icons.html,
    'css': Icons.css,
    'scss': Icons.css,
    'md': Icons.article,
    'yaml': Icons.settings,
    'yml': Icons.settings,
    'py': Icons.code,
    'java': Icons.code,
    'go': Icons.code,
    'rs': Icons.code,
    'cpp': Icons.code,
    'c': Icons.code,
    'swift': Icons.apple,
    'kt': Icons.android,
    'sh': Icons.terminal,
    'sql': Icons.storage,
    'xml': Icons.code,
    'txt': Icons.text_snippet,
    'png': Icons.image,
    'jpg': Icons.image,
    'jpeg': Icons.image,
    'svg': Icons.image,
    'gif': Icons.image,
  };

  // File color mappings
  static final Map<String, Color> _fileColorMap = {
    'dart': Color(0xFF00B4AB),
    'js': Color(0xFFF7DF1E),
    'ts': Color(0xFF3178C6),
    'tsx': Color(0xFF3178C6),
    'jsx': Color(0xFFF7DF1E),
    'html': Color(0xFFE34F26),
    'css': Color(0xFF1572B6),
    'scss': Color(0xFFCC6699),
    'py': Color(0xFF3776AB),
    'java': Color(0xFF007396),
    'go': Color(0xFF00ADD8),
    'rs': Color(0xFFDEA584),
    'swift': Color(0xFFFFAC45),
    'kt': Color(0xFF7F52FF),
    'json': Color(0xFF292929),
    'yaml': Color(0xFFCB171E),
    'md': Color(0xFF083FA1),
    'sql': Color(0xFF336791),
    'sh': Color(0xFF89E051),
  };
}

/// Context menu for file tree nodes
class FileTreeContextMenu extends StatelessWidget {
  final FileNode node;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;
  final VoidCallback? onNewFile;
  final VoidCallback? onNewFolder;

  const FileTreeContextMenu({
    super.key,
    required this.node,
    this.onRename,
    this.onDelete,
    this.onNewFile,
    this.onNewFolder,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (node.isDirectory) ...[
            _MenuItem(
              icon: Icons.insert_drive_file,
              label: '新建文件',
              onTap: onNewFile,
            ),
            _MenuItem(
              icon: Icons.create_new_folder,
              label: '新建文件夹',
              onTap: onNewFolder,
            ),
            const Divider(color: AppTheme.divider, height: 8),
          ],
          _MenuItem(
            icon: Icons.edit,
            label: '重命名',
            onTap: onRename,
          ),
          const Divider(color: AppTheme.divider, height: 8),
          _MenuItem(
            icon: Icons.delete_outline,
            label: '删除',
            iconColor: AppTheme.error,
            textColor: AppTheme.error,
            onTap: onDelete,
          ),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? iconColor;
  final Color? textColor;
  final VoidCallback? onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    this.iconColor,
    this.textColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        onTap?.call();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: iconColor ?? AppTheme.textSecondary,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: textColor ?? AppTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
