// lib/screens/mcp_manager_screen.dart
// MCP Manager Screen - MCP server management interface
// MCP 服务器管理界面

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../models/skill_model.dart';
import '../providers/skill_provider.dart';
import '../services/skill_manager_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// MCP Manager Screen
// ═══════════════════════════════════════════════════════════════════════════

/// MCP Manager Screen
///
/// Shows all MCP servers:
/// - Built-in servers (from skills)
/// - Custom servers (user-added)
///
/// Each server card displays:
/// - Server name + type badge (stdio/sse)
/// - Command or URL
/// - Status indicator (running/stopped/error)
/// - Enable toggle switch
/// - Environment variables (expandable)
/// - Logs (expandable)
class McpManagerScreen extends ConsumerStatefulWidget {
  const McpManagerScreen({super.key});

  @override
  ConsumerState<McpManagerScreen> createState() => _McpManagerScreenState();
}

class _McpManagerScreenState extends ConsumerState<McpManagerScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _commandController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();
  String _newServerType = 'stdio';

  @override
  void dispose() {
    _nameController.dispose();
    _commandController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final servers = ref.watch(mcpServersProvider);

    if (servers.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: servers.length + 1, // +1 for header
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildHeader(servers);
        }
        final server = servers[index - 1];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: McpServerCard(server: server),
        );
      },
    );
  }

  // ── Header ─────────────────────────────────────

  Widget _buildHeader(List<McpServer> servers) {
    final running = servers.where((s) => s.isRunning).length;
    final enabled = servers.where((s) => s.isEnabled).length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          // Stats row
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                _StatBox(
                  label: '总计',
                  value: '${servers.length}',
                  color: AppTheme.textSecondary,
                ),
                Container(
                  width: 1,
                  height: 30,
                  color: AppTheme.divider,
                  margin: const EdgeInsets.symmetric(horizontal: 14),
                ),
                _StatBox(
                  label: '已启用',
                  value: '$enabled',
                  color: AppTheme.primary,
                ),
                Container(
                  width: 1,
                  height: 30,
                  color: AppTheme.divider,
                  margin: const EdgeInsets.symmetric(horizontal: 14),
                ),
                _StatBox(
                  label: '运行中',
                  value: '$running',
                  color: AppTheme.success,
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _showMcpHubRegistrySheet,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    side: const BorderSide(color: AppTheme.border),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: const Size(0, 36),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.travel_explore_outlined, size: 16),
                  label: const Text(
                    'Registry',
                    style: TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Add button
                ElevatedButton.icon(
                  onPressed: _showAddServerDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: AppTheme.textOnPrimary,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    minimumSize: const Size(0, 36),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text(
                    '登记',
                    style: TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Status legend
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _StatusLegend(
                  label: '运行中',
                  color: Color(McpServerStatus.running.colorHex),
                ),
                const SizedBox(width: 12),
                _StatusLegend(
                  label: '已停止',
                  color: Color(McpServerStatus.stopped.colorHex),
                ),
                const SizedBox(width: 12),
                _StatusLegend(
                  label: '启动中',
                  color: Color(McpServerStatus.starting.colorHex),
                ),
                const SizedBox(width: 12),
                _StatusLegend(
                  label: '错误',
                  color: Color(McpServerStatus.error.colorHex),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  // ── Empty State ────────────────────────────────

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Center(
              child: Icon(
                Icons.dns_outlined,
                size: 36,
                color: AppTheme.textTertiary,
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            '暂无 MCP 服务器',
            style: TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.textTertiary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '装载带有 MCP 服务器的 Skill，或手动登记自定义服务器',
            style: TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 13,
              color: AppTheme.textTertiary.withOpacity(0.7),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _showAddServerDialog,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: AppTheme.textOnPrimary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.add, size: 18),
            label: const Text(
              '登记 MCP 服务器',
              style: TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Add Server Dialog
  // ═══════════════════════════════════════════════════════════════════════

  void _showMcpHubRegistrySheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.74,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          builder: (context, scrollController) {
            return FutureBuilder<List<McpServer>>(
              future: ref.read(skillManagerServiceProvider).searchMcpRegistryServers(limit: 10),
              builder: (context, snapshot) {
                final servers = snapshot.data ?? const <McpServer>[];
                return ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppTheme.textTertiary.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'MCP Registry',
                      style: TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Only public GitHub metadata is imported. No registry account is required. Servers are registered disabled until you review command, env, and permissions.',
                      style: TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 13,
                        height: 1.35,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (snapshot.connectionState != ConnectionState.done)
                      const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                    else if (servers.isEmpty)
                      const Text(
                        'No MCP candidates found.',
                        style: TextStyle(color: AppTheme.textTertiary),
                      )
                    else
                      for (final server in servers) ...[
                        _RegistryMcpTile(
                          server: server,
                          onTap: () => _showMcpRegistryPreview(server),
                        ),
                        const SizedBox(height: 10),
                      ],
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  void _showMcpRegistryPreview(McpServer server) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.border),
        ),
        title: Text(server.name, style: const TextStyle(color: AppTheme.textPrimary)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                server.description ?? 'No description provided.',
                style: const TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 13,
                  height: 1.4,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              _PreviewLine(label: 'Type', value: server.type),
              _PreviewLine(label: 'Command', value: server.command.isEmpty ? 'Review upstream docs before running.' : server.command),
              if (server.env.isNotEmpty) _PreviewLine(label: 'Env', value: server.env.keys.join(', ')),
              const SizedBox(height: 10),
              const Text(
                'Safety: registering does not start this MCP server. Enable it later only after reviewing secrets and workspace scope.',
                style: TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 12,
                  height: 1.35,
                  color: AppTheme.warning,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.of(context).pop();
              await _registerMcpRegistryCandidate(server);
            },
            icon: const Icon(Icons.add_link_outlined, size: 16),
            label: const Text('Register disabled'),
          ),
        ],
      ),
    );
  }

  Future<void> _registerMcpRegistryCandidate(McpServer server) async {
    final candidate = server.copyWith(
      isEnabled: false,
      status: McpServerStatus.stopped,
      registeredAt: DateTime.now(),
    );
    try {
      await ref.read(skillManagerServiceProvider).addCustomMcpServer(candidate);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已注册但未启用: ${candidate.name}'),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('注册失败: $e'),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showAddServerDialog() {
    _nameController.clear();
    _commandController.clear();
    _urlController.clear();
    _newServerType = 'stdio';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppTheme.border),
          ),
          title: const Text(
            '登记 MCP 服务器',
            style: TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => _polishMcpDraft(setState),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      side: const BorderSide(color: AppTheme.border),
                    ),
                    icon: const Icon(Icons.auto_awesome_outlined, size: 16),
                    label: const Text(
                      'AI 润色草案',
                      style: TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Server name
                TextField(
                  controller: _nameController,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontBody,
                    fontSize: 14,
                    color: AppTheme.textPrimary,
                  ),
                  decoration: InputDecoration(
                    labelText: '服务器名称',
                    hintText: '例如: GitHub MCP',
                    labelStyle: const TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                    filled: true,
                    fillColor: AppTheme.surfaceInput,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Type selector
                Row(
                  children: [
                    Expanded(
                      child: _TypeOption(
                        label: 'stdio (本地命令)',
                        value: 'stdio',
                        groupValue: _newServerType,
                        onChanged: (v) => setState(() => _newServerType = v!),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _TypeOption(
                        label: 'sse (远程地址)',
                        value: 'sse',
                        groupValue: _newServerType,
                        onChanged: (v) => setState(() => _newServerType = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Command or URL based on type
                if (_newServerType == 'stdio')
                  TextField(
                    controller: _commandController,
                    style: const TextStyle(
                      fontFamily: AppTheme.fontCode,
                      fontSize: 13,
                      color: AppTheme.textPrimary,
                    ),
                    decoration: InputDecoration(
                      labelText: '命令',
                      hintText: 'npx -y @modelcontextprotocol/server-github',
                      labelStyle: const TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                      hintStyle: const TextStyle(
                        fontFamily: AppTheme.fontCode,
                        fontSize: 12,
                        color: AppTheme.textTertiary,
                      ),
                      filled: true,
                      fillColor: AppTheme.surfaceInput,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppTheme.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
                      ),
                    ),
                  )
                else
                  TextField(
                    controller: _urlController,
                    style: const TextStyle(
                      fontFamily: AppTheme.fontCode,
                      fontSize: 13,
                      color: AppTheme.textPrimary,
                    ),
                    decoration: InputDecoration(
                      labelText: 'SSE URL',
                      hintText: 'https://mcp.example.com/sse',
                      labelStyle: const TextStyle(
                        fontFamily: AppTheme.fontBody,
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                      hintStyle: const TextStyle(
                        fontFamily: AppTheme.fontCode,
                        fontSize: 12,
                        color: AppTheme.textTertiary,
                      ),
                      filled: true,
                      fillColor: AppTheme.surfaceInput,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppTheme.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                '取消',
                style: TextStyle(fontFamily: AppTheme.fontBody, color: AppTheme.textSecondary),
              ),
            ),
            ElevatedButton(
              onPressed: () => _addServer(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: AppTheme.textOnPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text(
                '登记',
                style: TextStyle(fontFamily: AppTheme.fontBody, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _polishMcpDraft(StateSetter dialogSetState) {
    final endpoint = _newServerType == 'stdio'
        ? _commandController.text.trim()
        : _urlController.text.trim();
    if (endpoint.isEmpty && _nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('先输入命令或 URL，再润色 MCP 草案'),
          backgroundColor: AppTheme.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    dialogSetState(() {
      if (_nameController.text.trim().isEmpty) {
        _nameController.text = _inferMcpName(endpoint, _newServerType);
      }
      if (_newServerType == 'stdio') {
        _commandController.text = _commandController.text.trim().replaceAll(RegExp(r'\s+'), ' ');
      } else {
        _urlController.text = _urlController.text.trim();
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已按 MCP 模板整理名称和入口；登记前仍需人工审核命令、密钥和权限范围。'),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _inferMcpName(String endpoint, String type) {
    final text = endpoint.trim();
    if (text.isEmpty) return type == 'sse' ? 'Remote MCP Server' : 'Custom MCP Server';
    if (type == 'sse') {
      final uri = Uri.tryParse(text);
      final host = uri?.host;
      if (host != null && host.isNotEmpty) {
        final name = host.split('.').where((part) => part.isNotEmpty && part != 'www').take(2).join(' ');
        return name.isEmpty ? 'Remote MCP Server' : '${_titleCase(name)} MCP';
      }
      return 'Remote MCP Server';
    }
    final packageMatch = RegExp(r'(@[\w.-]+/[\w.-]+|[\w.-]*mcp[\w.-]*|server-[\w.-]+)', caseSensitive: false)
        .firstMatch(text);
    final raw = packageMatch?.group(0) ?? text.split(RegExp(r'\s+')).last;
    final clean = raw
        .replaceAll('@modelcontextprotocol/', '')
        .replaceAll('@', '')
        .replaceAll(RegExp(r'[-_/]+'), ' ')
        .trim();
    return clean.isEmpty ? 'Custom MCP Server' : '${_titleCase(clean)} MCP';
  }

  String _titleCase(String value) {
    return value
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + (part.length > 1 ? part.substring(1) : ''))
        .join(' ');
  }

  Future<void> _addServer(BuildContext dialogContext) async {
    final name = _nameController.text.trim();
    final command = _commandController.text.trim();
    final url = _urlController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请输入服务器名称'),
          backgroundColor: AppTheme.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_newServerType == 'stdio' && command.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请输入命令'),
          backgroundColor: AppTheme.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_newServerType == 'sse' && url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请输入 SSE URL'),
          backgroundColor: AppTheme.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    Navigator.of(dialogContext).pop();

    final serverId = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    final server = McpServer(
      id: serverId,
      name: name,
      type: _newServerType,
      command: _newServerType == 'stdio' ? command : '',
      url: _newServerType == 'sse' ? url : null,
      registeredAt: DateTime.now(),
    );

    try {
      await ref.read(skillManagerServiceProvider).addCustomMcpServer(server);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('MCP 服务器已登记，默认不会自动启动'),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('登记失败: $e'),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MCP Server Card
// ═══════════════════════════════════════════════════════════════════════════

/// Card displaying an MCP server with status, toggle, and expandable details.
class McpServerCard extends ConsumerStatefulWidget {
  final McpServer server;

  const McpServerCard({super.key, required this.server});

  @override
  ConsumerState<McpServerCard> createState() => _McpServerCardState();
}

class _McpServerCardState extends ConsumerState<McpServerCard> {
  bool _showDetails = false;

  @override
  Widget build(BuildContext context) {
    final server = widget.server;
    final statusColor = Color(server.status.colorHex);

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: server.isEnabled ? AppTheme.primary.withOpacity(0.3) : AppTheme.border,
        ),
      ),
      child: Column(
        children: [
          // Main row
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Status indicator
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                        boxShadow: server.isRunning
                            ? [
                                BoxShadow(
                                  color: statusColor.withOpacity(0.4),
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Icon
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: server.isEnabled
                            ? AppTheme.primary.withOpacity(0.12)
                            : AppTheme.surfaceHover,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Center(
                        child: Icon(
                          server.isStdio ? Icons.terminal : Icons.cloud,
                          size: 18,
                          color: server.isEnabled ? AppTheme.primary : AppTheme.textTertiary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Name + Type badge
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  server.name,
                                  style: TextStyle(
                                    fontFamily: AppTheme.fontBody,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: server.isEnabled ? AppTheme.textPrimary : AppTheme.textSecondary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              _TypeBadge(type: server.type),
                              const SizedBox(width: 8),
                              Text(
                                server.status.displayName,
                                style: TextStyle(
                                  fontFamily: AppTheme.fontBody,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: statusColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Toggle switch
                    SizedBox(
                      height: 32,
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: Switch.adaptive(
                          value: server.isEnabled,
                          onChanged: (_) => _toggleServer(server.id),
                          activeColor: AppTheme.primary,
                          activeTrackColor: AppTheme.primary.withOpacity(0.3),
                        ),
                      ),
                    ),
                  ],
                ),

                // Command or URL
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundElevated,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Text(
                    server.isStdio ? server.command : (server.url ?? ''),
                    style: const TextStyle(
                      fontFamily: AppTheme.fontCode,
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // Expandable details
          if (_showDetails)
            _buildDetails(server),

          // Bottom bar
          Container(
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: AppTheme.divider),
              ),
            ),
            child: Row(
              children: [
                // Expand/collapse
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _showDetails = !_showDetails),
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _showDetails ? Icons.expand_less : Icons.expand_more,
                            size: 16,
                            color: AppTheme.textTertiary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _showDetails ? '收起详情' : '查看详情',
                            style: const TextStyle(
                              fontFamily: AppTheme.fontBody,
                              fontSize: 12,
                              color: AppTheme.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                Container(width: 1, height: 24, color: AppTheme.divider),

                // Remove (for custom servers)
                if (server.skillIds.isEmpty)
                  Expanded(
                    child: InkWell(
                      onTap: () => _confirmRemove(server),
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.delete_outline, size: 14, color: AppTheme.error.withOpacity(0.7)),
                            const SizedBox(width: 4),
                            Text(
                              '移除',
                              style: TextStyle(
                                fontFamily: AppTheme.fontBody,
                                fontSize: 12,
                                color: AppTheme.error.withOpacity(0.7),
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
        ],
      ),
    );
  }

  Widget _buildDetails(McpServer server) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(color: AppTheme.divider, height: 1),
          const SizedBox(height: 12),

          // Server ID
          _DetailRow(label: 'ID', value: server.id),
          const SizedBox(height: 8),

          // Type
          _DetailRow(label: '类型', value: server.isStdio ? 'stdio (标准输入输出)' : 'sse (服务器推送)'),
          const SizedBox(height: 8),

          // Version
          if (server.version != null)
            _DetailRow(label: '版本', value: server.version!),

          if (server.version != null) const SizedBox(height: 8),

          // Registered skills
          if (server.skillIds.isNotEmpty) ...[
            _DetailRow(label: '来源技能', value: server.skillIds.join(', ')),
            const SizedBox(height: 8),
          ],

          // Last connected
          if (server.lastConnectedAt != null)
            _DetailRow(
              label: '上次连接',
              value: _formatDateTime(server.lastConnectedAt!),
            ),

          if (server.lastConnectedAt != null) const SizedBox(height: 8),

          // Environment variables
          if (server.env.isNotEmpty) ...[
            const Text(
              '环境变量',
              style: TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            ...server.env.entries.map((e) => Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 4),
                  child: _DetailRow(label: e.key, value: '${e.value}'),
                )),
          ],

          // Error message
          if (server.errorMessage != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.error.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.error_outline, size: 14, color: AppTheme.error),
                      SizedBox(width: 6),
                      Text(
                        '错误信息',
                        style: TextStyle(
                          fontFamily: AppTheme.fontBody,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.error,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    server.errorMessage!,
                    style: const TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 12,
                      color: AppTheme.error,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Tools list
          if (server.hasTools) ...[
            const SizedBox(height: 12),
            const Text(
              '可用工具',
              style: TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            ...server.tools.map((tool) => Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundElevated,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.build_outlined, size: 14, color: AppTheme.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tool.name,
                              style: const TextStyle(
                                fontFamily: AppTheme.fontCode,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            Text(
                              tool.description,
                              style: const TextStyle(
                                fontFamily: AppTheme.fontBody,
                                fontSize: 11,
                                color: AppTheme.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }

  Future<void> _toggleServer(String serverId) async {
    try {
      await ref.read(skillManagerServiceProvider).toggleMcpServer(serverId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('操作失败: $e'),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _confirmRemove(McpServer server) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.border),
        ),
        title: const Text(
          '确认移除',
          style: TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        content: Text(
          '确定要移除 MCP 服务器「${server.name}」吗？',
          style: const TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 14,
            color: AppTheme.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              '取消',
              style: TextStyle(fontFamily: AppTheme.fontBody, color: AppTheme.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              try {
                await ref.read(skillManagerServiceProvider).removeMcpServer(server.id);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('MCP 服务器已移除'),
                      backgroundColor: AppTheme.success,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('移除失败: $e'),
                      backgroundColor: AppTheme.error,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: AppTheme.textOnPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text(
              '移除',
              style: TextStyle(fontFamily: AppTheme.fontBody, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Supporting Widgets
// ═══════════════════════════════════════════════════════════════════════════

/// Stat box showing a label-value pair.
class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatBox({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 11,
            color: AppTheme.textTertiary,
          ),
        ),
      ],
    );
  }
}

/// Status legend dot with label.
class _StatusLegend extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusLegend({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontFamily: AppTheme.fontBody,
            fontSize: 11,
            color: AppTheme.textTertiary,
          ),
        ),
      ],
    );
  }
}

class _RegistryMcpTile extends StatelessWidget {
  const _RegistryMcpTile({
    required this.server,
    required this.onTap,
  });

  final McpServer server;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.backgroundElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.account_tree_outlined, color: AppTheme.primary, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    server.name,
                    style: const TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    server.description ?? server.command,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppTheme.fontBody,
                      fontSize: 12,
                      height: 1.35,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _TypeBadge(type: server.type),
                      const _RegistryPill(label: 'disabled preview'),
                      if (server.env.isNotEmpty) const _RegistryPill(label: 'env required'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: AppTheme.textTertiary),
          ],
        ),
      ),
    );
  }
}

class _RegistryPill extends StatelessWidget {
  const _RegistryPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.warning.withOpacity(0.10),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppTheme.warning.withOpacity(0.22)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: AppTheme.fontBody,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: AppTheme.warning,
        ),
      ),
    );
  }
}

class _PreviewLine extends StatelessWidget {
  const _PreviewLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: AppTheme.fontBody,
                fontSize: 12,
                color: AppTheme.textTertiary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: AppTheme.fontCode,
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

/// Type badge showing "stdio" or "sse".
class _TypeBadge extends StatelessWidget {
  final String type;

  const _TypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final isStdio = type == 'stdio';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isStdio ? AppTheme.accent.withOpacity(0.15) : AppTheme.info.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        type.toUpperCase(),
        style: TextStyle(
          fontFamily: AppTheme.fontCode,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: isStdio ? AppTheme.accent : AppTheme.info,
        ),
      ),
    );
  }
}

/// Radio option for server type selection.
class _TypeOption extends StatelessWidget {
  final String label;
  final String value;
  final String groupValue;
  final ValueChanged<String?>? onChanged;

  const _TypeOption({
    required this.label,
    required this.value,
    required this.groupValue,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    return InkWell(
      onTap: () => onChanged?.call(value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary.withOpacity(0.12) : AppTheme.surfaceHover,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppTheme.primary.withOpacity(0.5) : AppTheme.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: Radio<String>(
                value: value,
                groupValue: groupValue,
                onChanged: onChanged,
                activeColor: AppTheme.primary,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: AppTheme.fontBody,
                  fontSize: 12,
                  color: selected ? AppTheme.primary : AppTheme.textSecondary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Detail row with label and value.
class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 12,
              color: AppTheme.textTertiary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontFamily: AppTheme.fontBody,
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
